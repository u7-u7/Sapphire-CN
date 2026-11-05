import Foundation
import CoreGraphics
import Darwin
#if !NOTIFICATION_RECOVERY_TESTING
import AppKit
import ApplicationServices
import Security
#endif

enum NotificationRecoveryProcessIdentity {
    static func startedAt(_ pid: Int32) -> TimeInterval? {
        var info = proc_bsdinfo()
        let bytes = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, bytes) == bytes else { return nil }
        return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
    }

    static func executable(_ pid: Int32) -> String? {
        var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { return nil }
        return String(cString: bytes)
    }

    static func isAlive(_ pid: Int32, startedAt expected: TimeInterval?) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        // 元信息尚不可读时保守认为活跃，不能抢删另一个恢复事务的预备日志。
        guard let expected, let actual = startedAt(pid) else { return true }
        return abs(expected - actual) < 0.01
    }
}

enum NotificationRecoveryPathPolicy {
    static let mainName = "Sapphire"
    static let agentName = "SapphireNotificationRecovery"

    static func companion(for mainExecutable: URL) -> URL? {
        let main = mainExecutable.resolvingSymlinksInPath().standardizedFileURL
        let directory = main.deletingLastPathComponent()
        guard main.lastPathComponent == mainName, directory.lastPathComponent == "MacOS",
              directory.deletingLastPathComponent().lastPathComponent == "Contents",
              directory.deletingLastPathComponent().deletingLastPathComponent().pathExtension.lowercased() == "app" else { return nil }
        return directory.appendingPathComponent(agentName)
    }

    static func validPair(parentPath: String, agentPath: String) -> Bool {
        let parent = URL(fileURLWithPath: parentPath).resolvingSymlinksInPath().standardizedFileURL
        let agent = URL(fileURLWithPath: agentPath).resolvingSymlinksInPath().standardizedFileURL
        return companion(for: parent) == agent && agent.lastPathComponent == agentName
    }
}

struct NotificationRecoverySigningIdentity: Equatable {
    let identifier: String
    let team: String

    var isValid: Bool { !identifier.isEmpty && !team.isEmpty }
    func matches(_ other: Self) -> Bool { isValid && other.isValid && self == other }
}

struct NotificationWindowTarget: Codable, Hashable, Sendable {
    let pid: Int32
    let windowID: UInt32
}

/// 恢复日志只保存窗口几何与进程身份，不包含任何通知内容。
struct NotificationWindowLease: Codable, Equatable, Sendable {
    let target: NotificationWindowTarget
    let processStartedAt: TimeInterval
    let originalX: Double
    let originalY: Double
    let width: Double
    let height: Double
    let parkedX: Double
    let parkedY: Double

    var isSane: Bool {
        target.pid > 1 && target.windowID > 0
            && [processStartedAt, originalX, originalY, width, height, parkedX, parkedY].allSatisfy(\.isFinite)
            && processStartedAt > 0
            && abs(originalX) < 25000 && abs(originalY) < 25000
            && width > 0 && height > 0 && width < 30000 && height < 30000
            && parkedX == 32000 && parkedY == 32000
    }

    func matches(startedAt: TimeInterval, x: Double, y: Double) -> Bool {
        abs(processStartedAt - startedAt) < 0.01 && abs(parkedX - x) < 2 && abs(parkedY - y) < 2
    }

    func restorationOrigin(displays: [CGRect], mainDisplay: CGRect) -> CGPoint {
        let original = CGPoint(x: originalX, y: originalY)
        return displays.contains(where: { $0.contains(original) }) ? original : mainDisplay.origin
    }
}

enum NotificationRecoveryLeasePolicy {
    static let timeout: TimeInterval = 2

    static func retryDelay(failures: Int) -> TimeInterval {
        min(5, Double(1 << min(3, max(0, failures - 1))))
    }

    static func expired(lastHeartbeat: TimeInterval, now: TimeInterval, parentAlive: Bool) -> Bool {
        !parentAlive || !lastHeartbeat.isFinite || !now.isFinite || now < lastHeartbeat || now - lastHeartbeat > timeout
    }
}

struct NotificationRecoveryMessage: Codable, Sendable {
    let kind: String
    var requestID: UUID? = nil
    var target: NotificationWindowTarget? = nil
    var lease: NotificationWindowLease? = nil
    var success: Bool? = nil
}

struct NotificationRecoveryLineBuffer {
    private var buffer = Data()
    static let maximumBytes = 64 * 1024

    mutating func append(_ data: Data) throws -> [NotificationRecoveryMessage] {
        guard buffer.count + data.count <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        buffer.append(data)
        var messages: [NotificationRecoveryMessage] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            messages.append(try JSONDecoder().decode(NotificationRecoveryMessage.self, from: line))
        }
        return messages
    }

    static func encode(_ message: NotificationRecoveryMessage) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(10)
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        return data
    }
}

enum NotificationRecoverySocket {
    static func makeNonBlocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && (flags & O_NONBLOCK != 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0)
    }

    /// nil 表示当前无需处理；空 Data 才表示 EOF 或不可恢复的读取失败。
    static func read(from descriptor: Int32) -> Data? {
        var bytes = [UInt8](repeating: 0, count: NotificationRecoveryLineBuffer.maximumBytes)
        let count = Darwin.recv(descriptor, &bytes, bytes.count, MSG_DONTWAIT)
        if count >= 0 { return Data(bytes.prefix(count)) }
        return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? nil : Data()
    }

    static func write(_ data: Data, to descriptor: Int32) -> Bool {
        guard data.count <= NotificationRecoveryLineBuffer.maximumBytes else { return false }
        // 使用非阻塞系统调用；背压时立即停用接管，不能让 IPC 阻塞恢复主线程。
        guard makeNonBlocking(descriptor) else { return false }
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.send(descriptor, base.advanced(by: offset), bytes.count - offset, MSG_DONTWAIT)
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}

struct NotificationRecoveryJournal {
    struct Envelope: Codable {
        let ownerPID: Int32
        let createdAt: TimeInterval
        let ownerStartedAt: TimeInterval?
        let leases: [NotificationWindowLease]
    }
    let url: URL

    func write(_ leases: [NotificationWindowLease]) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard leases.count <= 16 else { throw CocoaError(.fileWriteOutOfSpace) }
        let previous = manager.fileExists(atPath: url.path) ? try readEnvelope() : nil
        let startedAt = NotificationRecoveryProcessIdentity.startedAt(getpid())
        let ownerStartedAt: TimeInterval?
        if let previous { ownerStartedAt = previous.ownerStartedAt }
        else { ownerStartedAt = startedAt }
        let envelope = Envelope(ownerPID: previous?.ownerPID ?? getpid(),
                                createdAt: previous?.createdAt ?? Date().timeIntervalSince1970,
                                ownerStartedAt: ownerStartedAt, leases: leases)
        let data = try JSONEncoder().encode(envelope)
        guard data.count < NotificationRecoveryLineBuffer.maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func read() throws -> [NotificationWindowLease] { try readEnvelope().leases }

    func readEnvelope() throws -> Envelope {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max < NotificationRecoveryLineBuffer.maximumBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.ownerPID > 0, envelope.createdAt.isFinite,
              envelope.leases.count <= 16, envelope.leases.allSatisfy(\.isSane) else { throw CocoaError(.fileReadCorruptFile) }
        return envelope
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sapphire-CN/notification-recovery", isDirectory: true)
    }
}

#if !NOTIFICATION_RECOVERY_TESTING

enum NotificationRecoveryCodeIdentity {
    private static func requirement() -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    private static func information(_ pid: Int32) -> [String: Any]? {
        var code: SecCode?
        let status: OSStatus
        if pid == getpid() { status = SecCodeCopySelf([], &code) }
        else { status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [], &code) }
        guard status == errSecSuccess, let code, let requirement = requirement(),
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else { return nil }
        return information as? [String: Any]
    }

    static func identity(_ pid: Int32) -> NotificationRecoverySigningIdentity? {
        guard let info = information(pid), let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String else { return nil }
        let identity = NotificationRecoverySigningIdentity(identifier: identifier, team: team)
        return identity.isValid ? identity : nil
    }

    static func companionMatches(_ url: URL, parent: NotificationRecoverySigningIdentity) -> Bool {
        var code: SecStaticCode?
        guard parent.isValid, let requirement = requirement(),
              SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess else { return false }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any], let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String else { return false }
        return parent.matches(NotificationRecoverySigningIdentity(identifier: identifier, team: team))
    }

    static func isNotificationCenter(_ pid: Int32) -> Bool {
        information(pid)?[kSecCodeInfoIdentifier as String] as? String == "com.apple.notificationcenterui"
    }
}

@MainActor
enum NotificationRecoveryAX {
    static func window(_ target: NotificationWindowTarget) -> (AXUIElement, Date)? {
        guard target.pid > 0, target.windowID > 0,
              let process = NSRunningApplication(processIdentifier: target.pid),
              process.bundleIdentifier == "com.apple.notificationcenterui", NotificationRecoveryCodeIdentity.isNotificationCenter(target.pid),
              let processStart = NotificationRecoveryProcessIdentity.startedAt(target.pid) else { return nil }
        let startedAt = Date(timeIntervalSince1970: processStart)
        let application = AX.application(pid: target.pid)
        AX.setMessagingTimeout(0.1, on: application)
        for window in AX.elements(kAXWindowsAttribute as String, of: application).prefix(16) {
            AX.setMessagingTimeout(0.1, on: window)
            guard AX.windowID(of: window) == target.windowID,
                  AX.role(of: window) == "AXWindow", AX.subrole(of: window) == "AXSystemDialog" else { continue }
            return (window, startedAt)
        }
        return nil
    }

    static func lease(_ target: NotificationWindowTarget) -> NotificationWindowLease? {
        guard let (window, startedAt) = window(target), let frame = AX.windowFrame(of: window),
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width > 0, frame.height > 0,
              frame.width < 30000, frame.height < 30000,
              AX.isSettable(kAXPositionAttribute as String, of: window) else { return nil }
        // 不接受已经在保留区的未知窗口，不能把错误坐标当作恢复原点。
        guard abs(frame.minX) < 25000, abs(frame.minY) < 25000 else { return nil }
        let parked = CGRect(x: 32000, y: 32000, width: frame.width, height: frame.height)
        guard !displayBounds().contains(where: { $0.intersects(parked) }) else { return nil }
        return NotificationWindowLease(target: target, processStartedAt: startedAt.timeIntervalSince1970,
                                       originalX: frame.minX, originalY: frame.minY, width: frame.width, height: frame.height,
                                       parkedX: 32000, parkedY: 32000)
    }

    static func park(_ lease: NotificationWindowLease) -> Bool {
        guard let (window, startedAt) = window(lease.target),
              abs(startedAt.timeIntervalSince1970 - lease.processStartedAt) < 0.01,
              let frame = AX.windowFrame(of: window), frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return false }
        let desired = CGPoint(x: lease.parkedX, y: lease.parkedY)
        // 重复接管期间也可能发生显示器变化，不能继续使用已经进入屏幕的保留区。
        let parked = CGRect(origin: desired, size: frame.size)
        guard !displayBounds().contains(where: { $0.intersects(parked) }) else { return false }
        guard AX.set(kAXPositionAttribute as String, toPoint: desired, on: window),
              let actual = AX.point(kAXPositionAttribute as String, of: window) else { return false }
        return abs(actual.x - desired.x) < 2 && abs(actual.y - desired.y) < 2
    }

    enum RestoreResult: Equatable { case restored, gone, changed, failed }
    static func restore(_ lease: NotificationWindowLease) -> RestoreResult {
        guard kill(lease.target.pid, 0) == 0 || errno == EPERM else { return errno == ESRCH ? .gone : .failed }
        guard let processStart = NotificationRecoveryProcessIdentity.startedAt(lease.target.pid) else { return .failed }
        guard abs(processStart - lease.processStartedAt) < 0.01 else { return .gone }
        // LaunchServices 或签名服务暂时不可读不等于窗口销毁，不能丢掉唯一恢复记录。
        guard let process = NSRunningApplication(processIdentifier: lease.target.pid),
              process.bundleIdentifier == "com.apple.notificationcenterui",
              NotificationRecoveryCodeIdentity.isNotificationCenter(lease.target.pid) else { return .failed }
        let startedAt = Date(timeIntervalSince1970: processStart)
        guard AXIsProcessTrusted(), let (window, _) = window(lease.target) else {
            // 权限撤销或 AX 超时不能当作窗口已销毁，也不能主动弹授权来扩大权限。
            guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, lease.target.windowID) as? [[String: Any]] else { return .failed }
            return list.isEmpty ? .gone : .failed
        }
        guard let frame = AX.windowFrame(of: window), frame.minX.isFinite, frame.minY.isFinite else { return .failed }
        guard abs(frame.minX - lease.parkedX) < 2, abs(frame.minY - lease.parkedY) < 2 else { return .changed }
        guard lease.matches(startedAt: startedAt.timeIntervalSince1970, x: frame.minX, y: frame.minY) else { return .failed }
        // 显示器拔插会改变浮层尺寸；只恢复仍属于该租约的窗口位置，不回写旧尺寸。
        let origin = lease.restorationOrigin(displays: displayBounds(), mainDisplay: CGDisplayBounds(CGMainDisplayID()))
        guard AX.set(kAXPositionAttribute as String, toPoint: origin, on: window),
              let point = AX.point(kAXPositionAttribute as String, of: window),
              abs(point.x - origin.x) < 2, abs(point.y - origin.y) < 2 else { return .failed }
        return .restored
    }

    private static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 64 else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [CGDisplayBounds(CGMainDisplayID())] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }
}

/// 父进程只发租约请求；独立同用户看护在记录原坐标后执行移动。
@MainActor
final class NotificationWindowRecovery {
    private(set) var isReady = false
    var onFailure: (() -> Void)?
    private var process: Process?
    private var socket: FileHandle?
    private var heartbeat: Timer?
    private var buffer = NotificationRecoveryLineBuffer()
    private var pending: [UUID: CheckedContinuation<NotificationRecoveryMessage?, Never>] = [:]
    private var readyContinuation: CheckedContinuation<Bool, Never>?
    private var localLeases: [NotificationWindowTarget: NotificationWindowLease] = [:]
    private var failed = false
    private var stopping = false
    private var generation = UUID()
    private var lastAgentResponse = ProcessInfo.processInfo.systemUptime
    private(set) var lastRestoreSucceeded = true

    deinit {
        heartbeat?.invalidate()
        socket?.readabilityHandler = nil
        try? socket?.close()
    }

    var agentProcessIdentifier: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    static var isAgentProcess: Bool {
        CommandLine.arguments.contains("--notification-restore-agent")
            || NotificationRecoveryProcessIdentity.executable(getpid()).map { URL(fileURLWithPath: $0).lastPathComponent == NotificationRecoveryPathPolicy.agentName } == true
    }

    @discardableResult
    static func runAgentIfRequested() -> Bool {
        guard isAgentProcess else { return false }
        NSApp.setActivationPolicy(.prohibited)
        NotificationRestoreAgent.startFromArguments()
        return true
    }

    /// 关闭实时模式时也调用；这里只恢复本应用留下的特定通知窗口。
    @discardableResult
    static func recoverStaleWindows() -> Bool { recoverStaleWindows(exitedOwnerPID: nil) }

    private static func recoverStaleWindows(exitedOwnerPID: Int32?) -> Bool {
        let directory = NotificationRecoveryJournal.directory
        guard FileManager.default.fileExists(atPath: directory.path) else { return true }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("lease-") && $0.pathExtension == "json" }
            guard !files.isEmpty else { return true }
            guard AXIsProcessTrusted() else { return false }
            var success = files.count <= 32
            for file in files.prefix(32) {
                do {
                    let journal = NotificationRecoveryJournal(url: file)
                    let envelope = try journal.readEnvelope()
                    // 活跃看护可能正位于“写日志→移动”的事务间隙；不能抢删它的预备日志。
                    if envelope.ownerPID != exitedOwnerPID,
                       NotificationRecoveryProcessIdentity.isAlive(envelope.ownerPID, startedAt: envelope.ownerStartedAt) {
                        success = false
                        continue
                    }
                    let remaining = envelope.leases.filter { NotificationRecoveryAX.restore($0) == .failed }
                    if remaining.isEmpty { try journal.remove() }
                    else { try journal.write(remaining); success = false }
                } catch {
                    success = false
                    print("[NotificationRecovery] One stale journal could not be recovered: \(error)")
                }
            }
            return success
        } catch {
            print("[NotificationRecovery] Stale journal recovery failed: \(error)")
            return false
        }
    }

    func start() async -> Bool {
        if isReady { return true }
        guard process == nil, AXIsProcessTrusted(), Self.recoverStaleWindows(),
              let path = NotificationRecoveryProcessIdentity.executable(getpid()),
              let executable = NotificationRecoveryPathPolicy.companion(for: URL(fileURLWithPath: path)),
              let identity = NotificationRecoveryCodeIdentity.identity(getpid()),
              let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              FileManager.default.isExecutableFile(atPath: executable.path),
              NotificationRecoveryCodeIdentity.companionMatches(executable, parent: identity) else { return false }
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { return false }
        for fd in descriptors {
            var enabled: Int32 = 1
            guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0,
                  NotificationRecoverySocket.makeNonBlocking(fd),
                  fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
                close(descriptors[0]); close(descriptors[1]); return false
            }
        }
        let parent = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true)
        let child = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
        let task = Process(), session = UUID()
        task.executableURL = executable
        task.arguments = ["--notification-restore-agent", "--parent", String(getpid()), "--session", session.uuidString]
        task.standardInput = child; task.standardOutput = child; task.standardError = FileHandle.nullDevice
        failed = false; stopping = false; generation = session; buffer = NotificationRecoveryLineBuffer()
        localLeases.removeAll(); lastRestoreSucceeded = true
        socket = parent; process = task
        parent.readabilityHandler = { [weak self] handle in
            guard let data = NotificationRecoverySocket.read(from: handle.fileDescriptor) else { return }
            Task { @MainActor [weak self] in self?.receive(data, generation: session) }
        }
        task.terminationHandler = { [weak self] finished in
            let exitedPID = finished.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                self.restoreLocally(exitedOwnerPID: exitedPID)
                self.fail()
            }
        }
        return await withCheckedContinuation { continuation in
            // 先注册等待者再启动子进程，防止极快 ready 报文先于 continuation。
            readyContinuation = continuation
            do { try task.run(); try child.close() }
            catch { try? child.close(); fail(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.generation == session, !self.isReady else { return }
                self.fail()
            }
        }
    }

    func park(_ target: NotificationWindowTarget) async -> Bool {
        guard isReady, !stopping else { return false }
        let session = generation
        guard let reply = await request(NotificationRecoveryMessage(kind: "park", target: target)),
              reply.success == true, let lease = reply.lease, lease.target == target, lease.isSane,
              isReady, !failed, !stopping, generation == session else { return false }
        localLeases[target] = lease
        return true
    }

    func restoreAll() async {
        let reply = isReady ? await request(NotificationRecoveryMessage(kind: "restore")) : nil
        restoreLocally()
        if reply?.success == false || !lastRestoreSucceeded { fail() }
    }

    func stop() async {
        stopping = true
        await restoreAll()
        if isReady { _ = await request(NotificationRecoveryMessage(kind: "stop")) }
        closeTransport()
        process = nil
    }

    private func request(_ message: NotificationRecoveryMessage) async -> NotificationRecoveryMessage? {
        guard isReady else { return nil }
        let id = UUID(); var message = message; message.requestID = id
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            guard send(message) else { fail(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let waiting = self.pending.removeValue(forKey: id) else { return }
                waiting.resume(returning: nil)
                self.fail()
            }
        }
    }

    @discardableResult
    private func send(_ message: NotificationRecoveryMessage) -> Bool {
        guard let socket else { return false }
        do { return NotificationRecoverySocket.write(try NotificationRecoveryLineBuffer.encode(message), to: socket.fileDescriptor) }
        catch { return false }
    }

    private func receive(_ data: Data, generation: UUID) {
        guard self.generation == generation, !failed else { return }
        guard !data.isEmpty else { fail(); return }
        do {
            for reply in try buffer.append(data) {
                lastAgentResponse = ProcessInfo.processInfo.systemUptime
                if reply.kind == "ready" {
                    guard reply.success == true, !isReady, readyContinuation != nil else { fail(); return }
                    isReady = true
                    readyContinuation?.resume(returning: true); readyContinuation = nil
                    heartbeat = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            guard !NotificationRecoveryLeasePolicy.expired(lastHeartbeat: self.lastAgentResponse, now: ProcessInfo.processInfo.systemUptime, parentAlive: true),
                                  self.send(NotificationRecoveryMessage(kind: "heartbeat")) else { self.fail(); return }
                        }
                    }
                    RunLoop.main.add(heartbeat!, forMode: .common)
                } else if let id = reply.requestID, let continuation = pending.removeValue(forKey: id) {
                    if reply.kind == "restore", reply.success == true { localLeases.removeAll() }
                    continuation.resume(returning: reply)
                } else if reply.kind == "failure" { fail() }
            }
        } catch { fail() }
    }

    private func fail() {
        guard !failed else { return }
        failed = true
        let notify = !stopping
        closeTransport()
        restoreLocally()
        process = nil
        if notify { onFailure?() }
    }

    private func closeTransport() {
        isReady = false
        heartbeat?.invalidate(); heartbeat = nil
        socket?.readabilityHandler = nil
        try? socket?.close(); socket = nil
        readyContinuation?.resume(returning: false); readyContinuation = nil
        let requests = pending; pending.removeAll()
        for continuation in requests.values { continuation.resume(returning: nil) }
    }

    private func restoreLocally(exitedOwnerPID: Int32? = nil) {
        localLeases = localLeases.filter { NotificationRecoveryAX.restore($0.value) == .failed }
        let journalRecovered = Self.recoverStaleWindows(exitedOwnerPID: exitedOwnerPID)
        lastRestoreSucceeded = localLeases.isEmpty && journalRecovered
        if !lastRestoreSucceeded {
            print("[NotificationRecovery] Some windows could not be restored; recovery journal retained")
        }
    }
}

#endif
