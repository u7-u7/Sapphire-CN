import Foundation
import Security
import CryptoKit
import LocalAuthentication

/// 凭据选择与 usage 协议参考 CodexIsland（MIT），许可随目录保留。
/// 不读取 refreshToken、不写入 CLI 凭据，也不通过模型请求触发 token 更新。
enum ClaudeUsageClient {
    struct Credential: Sendable {
        let accessToken: String
        let plan: String?
        let expiresAt: Date?
        var identity: String {
            SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    static func fetch() async -> AIUsageReadResult {
        // 当前 CLI 明确选用 DeepSeek 时读取它的余额，不能借用另一套 Claude 订阅读数。
        if DeepSeekUsageClient.isConfigured(environment: configuredEnvironment()) {
            return await DeepSeekUsageClient.fetch(readCredential: {
                DeepSeekUsageClient.credential(environment: configuredEnvironment())
            })
        }
        return await fetch(readCredential: readCredential, request: request, unsupportedConfiguration: hasUnsupportedConfiguration)
    }

    /// fixture 注入只在内存中使用伪造凭据，不读取 Keychain、不请求额度服务。
    static func fetch(readCredential: () async -> Credential?, request: (Credential) async -> AIUsageReadResult,
                      unsupportedConfiguration: () -> Bool = { false }) async -> AIUsageReadResult {
        guard let credential = await readCredential() else {
            let failure: AIUsageFailure = unsupportedConfiguration() ? .unsupportedClaudeConfiguration : .authentication(.claude)
            return AIUsageReadResult(identity: nil, snapshot: nil, failure: failure)
        }
        if let expiry = credential.expiresAt, expiry <= Date() {
            return AIUsageReadResult(identity: credential.identity, snapshot: nil, failure: .authentication(.claude))
        }
        var result = await request(credential)
        let current = await readCredential()
        // 401/403 时仅重新读取本配置目录的登录一次；若 CLI 已轮换 token，可以重试新值。
        // 429 则立即退出，换 token 不能突破同账号的限流。
        if case .authentication? = result.failure,
           let current, current.identity != credential.identity {
            result = await request(current)
            let verified = await readCredential()
            if case .rateLimited? = result.failure {
                return AIUsageReadResult(identity: verified?.identity, snapshot: nil, failure: .rateLimited)
            }
            guard verified?.identity == current.identity else {
                return AIUsageReadResult(identity: nil, snapshot: nil, failure: .accountChanged)
            }
            return result
        }
        if case .rateLimited? = result.failure {
            return AIUsageReadResult(identity: current?.identity, snapshot: nil, failure: .rateLimited)
        }
        // 登录变化期间返回的旧结果不能被新账号接收；token 轮换也保守丢弃本次结果。
        guard current?.identity == credential.identity else {
            return AIUsageReadResult(identity: nil, snapshot: nil, failure: .accountChanged)
        }
        return result
    }

    private static func request(_ credential: Credential) async -> AIUsageReadResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.121", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: AIUsageNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIUsageFailure.transport }
            let failure = responseFailure(status: http.statusCode, data: data)
            if let failure { throw failure }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIUsageFailure.invalidResponse
            }
            let snapshot = AIUsageParser.claude(object, plan: credential.plan, at: Date()).expiringWindows(at: Date())
            return AIUsageReadResult(identity: credential.identity, snapshot: snapshot, failure: nil)
        } catch let failure as AIUsageFailure {
            return AIUsageReadResult(identity: credential.identity, snapshot: nil, failure: failure)
        } catch {
            let timedOut = (error as? URLError)?.code == .timedOut
            return AIUsageReadResult(identity: credential.identity, snapshot: nil, failure: timedOut ? .timeout : .transport)
        }
    }

    static func responseFailure(status: Int, data: Data) -> AIUsageFailure? {
        if status == 429 { return .rateLimited }
        if status == 401 || status == 403 { return .authentication(.claude) }
        guard status == 200 else { return .transport }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            return error["type"] as? String == "rate_limit_error" ? .rateLimited : .invalidResponse
        }
        return nil
    }

    private static func hasUnsupportedConfiguration() -> Bool {
        hasUnsupportedConfiguration(environment: configuredEnvironment(), settingsData: nil)
    }

    private static func configuredEnvironment() -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = configured.flatMap { $0.isEmpty ? nil : NSString(string: $0).expandingTildeInPath }
            ?? "\(NSHomeDirectory())/.claude"
        return effectiveEnvironment(environment: environment,
            settingsData: FileManager.default.contents(atPath: "\(directory)/settings.json"))
    }

    /// 普通 CLI 的 settings.env 覆盖 shell export；不加载项目配置，也不记录鉴权内容。
    static func effectiveEnvironment(environment: [String: String], settingsData: Data?) -> [String: String] {
        var effective = environment
        if let settingsData,
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
           let values = settings["env"] as? [String: Any] {
            effective.merge(values.compactMapValues { $0 as? String }) { _, configured in configured }
        }
        return effective
    }

    /// 仅在缺少订阅 OAuth 时解释 CLI 的 API 配置；不把第三方 token 发往官方 usage 接口。
    static func hasUnsupportedConfiguration(environment: [String: String], settingsData: Data?) -> Bool {
        let effective = effectiveEnvironment(environment: environment, settingsData: settingsData)
        let base = effective["ANTHROPIC_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !base.isEmpty, URLComponents(string: base)?.host?.lowercased() != "api.anthropic.com" { return true }
        return ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"].contains { key in
            !(effective[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
    }

    private static func readCredential() async -> Credential? {
        await Task.detached(priority: .utility) {
            let environment = ProcessInfo.processInfo.environment
            if let token = environment["CLAUDE_CODE_OAUTH_TOKEN"], !token.isEmpty {
                return Credential(accessToken: token, plan: nil, expiresAt: nil)
            }
            // 属性查询不返回密钥；仅筛选 Claude 的凭据项，避免把 MCP OAuth 项当订阅登录。
            for (service, account) in keychainItems(environment: environment) {
                guard let result = ProcessRunner.runSync(executablePath: "/usr/bin/security",
                    arguments: ["find-generic-password", "-s", service, "-a", account, "-w"], timeout: 3),
                    result.succeeded, let credential = decode(result.stdoutData),
                    credential.expiresAt.map({ $0 > Date() }) ?? true else { continue }
                return credential
            }
            let directory = environment["CLAUDE_CONFIG_DIR"] ?? "\(NSHomeDirectory())/.claude"
            guard let data = FileManager.default.contents(atPath: "\(directory)/.credentials.json") else { return nil }
            return decode(data)
        }.value
    }

    private static func decode(_ data: Data) -> Credential? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        // CLI expiresAt 使用毫秒；额度接口的 resets_at 使用秒，不能混用。
        let expiry = AIUsageParser.finiteNumber(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credential(accessToken: token, plan: oauth["subscriptionType"] as? String, expiresAt: expiry)
    }

    static func usesDefaultKeychain(environment: [String: String], home: String = NSHomeDirectory()) -> Bool {
        // 自定义目录的 Keychain suffix 是 CLI 私有规则；不猜测或遍历其他账号的 store。
        // 该情形只读明确配置目录下的 .credentials.json，缺失时引导用户登录。
        let defaultDirectory = URL(fileURLWithPath: "\(home)/.claude").standardizedFileURL.path
        for key in ["CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR"] {
            guard let path = environment[key], !path.isEmpty else { continue }
            let resolved = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
            if resolved != defaultDirectory { return false }
        }
        return true
    }

    private static func keychainItems(environment: [String: String]) -> [(String, String)] {
        guard usesDefaultKeychain(environment: environment) else { return [] }
        let context = LAContext()
        context.interactionNotAllowed = true
        let base = "Claude Code-credentials"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: base, kSecAttrAccount as String: NSUserName(),
            kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item -> (String, String)? in
            guard let service = item[kSecAttrService as String] as? String,
                  service == base,
                  let account = item[kSecAttrAccount as String] as? String, account == NSUserName() else { return nil }
            return (service, account)
        }.sorted { lhs, rhs in
            let left = (lhs.0 == base ? "0" : "1") + lhs.0 + (lhs.1 == NSUserName() ? "0" : "1")
            let right = (rhs.0 == base ? "0" : "1") + rhs.0 + (rhs.1 == NSUserName() ? "0" : "1")
            return left < right
        }
    }
}

final class AIUsageNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // OAuth 凭据仅发往固定 Anthropic endpoint，任何重定向都视为连接失败。
        completionHandler(nil)
    }
}
