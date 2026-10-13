import Foundation
import CryptoKit
import Darwin

/// 官方 app-server stdio 只查询账号与额度，不创建 thread/turn，也不发起登录或强制 token 刷新。
enum CodexUsageClient {
    static func fetch() async -> AIUsageReadResult {
        await Task.detached(priority: .utility) {
            guard let executable = executable() else {
                return AIUsageReadResult(identity: nil, snapshot: nil, failure: .missingCLI)
            }
            return fetchSync(executable: executable, fingerprint: credentialFingerprint, timeout: 25)
        }.value
    }

    /// 仅为离线 fixture 提供传输注入；测试不触及真实 CLI 或本机凭据。
    static func fetch(executablePath: String, fingerprint: @escaping @Sendable () -> String?, timeout: TimeInterval = 25) async -> AIUsageReadResult {
        await Task.detached(priority: .utility) {
            fetchSync(executable: executablePath, fingerprint: fingerprint, timeout: timeout)
        }.value
    }

    private static func fetchSync(executable: String, fingerprint: () -> String?, timeout: TimeInterval) -> AIUsageReadResult {
        let initialFingerprint = fingerprint()
        var identity: String?
        do {
            let rpc = try AIUsageCodexRPC(executable: executable, timeout: timeout)
            defer { rpc.close() }
            _ = try rpc.request("initialize", id: 0, params: ["clientInfo": [
                "name": "sapphire_usage", "title": "Sapphire AI Usage", "version": "1.0"]])
            try rpc.notify("initialized")
            let before = try account(try rpc.request("account/read", id: 1, params: ["refreshToken": false]))
            identity = accountIdentity(before, fingerprint: initialFingerprint)
            let limits = try rpc.request("account/rateLimits/read", id: 2)
            let after = try account(try rpc.request("account/read", id: 3, params: ["refreshToken": false]))
            let currentFingerprint = fingerprint()
            guard accountIdentity(after, fingerprint: currentFingerprint) == identity else {
                throw AIUsageFailure.accountChanged
            }
            let snapshot = AIUsageParser.codex(limits, plan: after["planType"] as? String, at: Date())
                .expiringWindows(at: Date())
            return AIUsageReadResult(identity: identity, snapshot: snapshot, failure: nil)
        } catch let failure as AIUsageFailure {
            return AIUsageReadResult(identity: identity, snapshot: nil, failure: failure)
        } catch {
            return AIUsageReadResult(identity: identity, snapshot: nil, failure: .transport)
        }
    }

    private static func account(_ result: [String: Any]) throws -> [String: Any] {
        guard let account = result["account"] as? [String: Any],
              let type = account["type"] as? String,
              ["chatgpt", "chatgptAuthTokens"].contains(type) else { throw AIUsageFailure.authentication(.codex) }
        return account
    }

    private static func accountIdentity(_ account: [String: Any], fingerprint: String?) -> String? {
        let email = account["email"] as? String
        guard email != nil || fingerprint != nil else { return nil }
        return hash("\(email ?? "")|\(fingerprint ?? "")")
    }

    /// 指纹只存内存；token 轮换也保守清理旧读数，避免跨账号保留上次额度。
    private static func credentialFingerprint() -> String? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
        guard let data = FileManager.default.contents(atPath: "\(home)/auth.json") else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func executable(home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        var candidates = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex", "\(home)/Applications/Codex.app/Contents/Resources/codex"]
        let versions = "\(home)/.nvm/versions/node"
        let versionNames = (try? FileManager.default.contentsOfDirectory(atPath: versions)) ?? []
        candidates += versionNames.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(versions)/\($0)/bin/codex" }
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// ProcessRunner 的单次命令接口不支持双向 RPC；这里仅封装有期限的 stdio 会话。
private final class AIUsageCodexRPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let buffer = AIUsageRPCBuffer()
    private let deadline: Date

    init(executable: String, timeout: TimeInterval) throws {
        deadline = Date().addingTimeInterval(timeout)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        // nvm/Homebrew 的脚本入口通常通过 env node 启动，GUI 的 PATH 需要补齐相邻 bin。
        var environment = ProcessInfo.processInfo.environment
        let bin = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        environment["PATH"] = "\(bin):/opt/homebrew/bin:/usr/local/bin:\(environment["PATH"] ?? "/usr/bin:/bin")"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // 子进程提前关闭 stdin 时只产生 EPIPE，不能让 SIGPIPE 杀死整个 Sapphire。
        // Darwin 的逐 descriptor 标志不会改变应用其他线程的信号行为。
        guard Darwin.fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw AIUsageFailure.transport
        }
        output.fileHandleForReading.readabilityHandler = { [buffer] handle in buffer.append(handle.availableData) }
        process.terminationHandler = { [buffer] _ in buffer.finished() }
        do { try process.run() }
        catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw AIUsageFailure.transport
        }
    }

    func request(_ method: String, id: Int, params: [String: Any]? = nil) throws -> [String: Any] {
        var packet: [String: Any] = ["id": id, "method": method]
        if let params { packet["params"] = params }
        try send(packet)
        let response = try buffer.response(id: id, until: deadline)
        if let error = response["error"] as? [String: Any] {
            // 服务端错误文字可能包含请求上下文，UI 仅获得固定的中文错误。
            let message = (error["message"] as? String ?? "").lowercased()
            if message.contains("429") || message.contains("rate limit") { throw AIUsageFailure.rateLimited }
            if message.contains("401") || message.contains("403") || message.contains("auth") || message.contains("login") {
                throw AIUsageFailure.authentication(.codex)
            }
            throw AIUsageFailure.invalidResponse
        }
        guard let result = response["result"] as? [String: Any] else { throw AIUsageFailure.invalidResponse }
        return result
    }

    func notify(_ method: String) throws { try send(["method": method, "params": [:]]) }

    private func send(_ packet: [String: Any]) throws {
        guard process.isRunning else { throw AIUsageFailure.transport }
        var data = try JSONSerialization.data(withJSONObject: packet, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        // 只发送四个很小的查询，大小远低于 pipe 缓冲，stdout 则始终被独立持续读取。
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        buffer.waitForExit(until: Date().addingTimeInterval(0.5))
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        buffer.waitForExit(until: Date().addingTimeInterval(0.5))
        output.fileHandleForReading.readabilityHandler = nil
        try? output.fileHandleForReading.close()
    }
}

private final class AIUsageRPCBuffer: @unchecked Sendable {
    private let condition = NSCondition()
    private var pending = Data()
    private var replies: [Int: [String: Any]] = [:]
    private var exited = false
    private var overflow = false

    func append(_ data: Data) {
        condition.lock()
        defer { condition.broadcast(); condition.unlock() }
        guard !overflow else { return }
        pending.append(data)
        if pending.count > 2_000_000 { overflow = true; pending.removeAll(); return }
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            guard let packet = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = packet["id"] as? Int, id >= 0, id <= 3,
                  packet["result"] != nil || packet["error"] != nil else { continue }
            replies[id] = packet
        }
    }

    func response(id: Int, until deadline: Date) throws -> [String: Any] {
        condition.lock()
        defer { condition.unlock() }
        while replies[id] == nil {
            if overflow { throw AIUsageFailure.invalidResponse }
            if exited { throw AIUsageFailure.transport }
            guard condition.wait(until: deadline) else { throw AIUsageFailure.timeout }
        }
        return replies.removeValue(forKey: id)!
    }

    func finished() {
        condition.lock()
        exited = true
        condition.broadcast()
        condition.unlock()
    }

    func waitForExit(until deadline: Date) {
        condition.lock()
        defer { condition.unlock() }
        while !exited, condition.wait(until: deadline) {}
    }
}
