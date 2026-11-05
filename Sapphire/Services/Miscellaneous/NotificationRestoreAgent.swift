#if !NOTIFICATION_RECOVERY_TESTING
import Foundation
import AppKit
import ApplicationServices
import Darwin

@MainActor
final class NotificationRestoreAgent {
    private static var active: NotificationRestoreAgent?
    private let parentPID: Int32
    private let journal: NotificationRecoveryJournal
    private var leases: [NotificationWindowTarget: NotificationWindowLease] = [:]
    private var buffer = NotificationRecoveryLineBuffer()
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var stoppingAt: TimeInterval?
    private var restoreFailures = 0

    private init(parentPID: Int32, session: UUID) {
        self.parentPID = parentPID
        journal = NotificationRecoveryJournal(url: NotificationRecoveryJournal.directory.appendingPathComponent("lease-\(session.uuidString).json"))
    }

    static func startFromArguments() {
        func argument(_ key: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: key), CommandLine.arguments.indices.contains(index + 1) else { return nil }
            return CommandLine.arguments[index + 1]
        }
        guard let rawParent = argument("--parent"), let parent = Int32(rawParent), parent > 1,
              getppid() == parent,
              let ownPath = NotificationRecoveryProcessIdentity.executable(getpid()),
              let parentPath = NotificationRecoveryProcessIdentity.executable(parent),
              NotificationRecoveryPathPolicy.validPair(parentPath: parentPath, agentPath: ownPath),
              let ownIdentity = NotificationRecoveryCodeIdentity.identity(getpid()),
              let parentIdentity = NotificationRecoveryCodeIdentity.identity(parent), ownIdentity.matches(parentIdentity),
              let rawSession = argument("--session"), let session = UUID(uuidString: rawSession), AXIsProcessTrusted() else {
            NSApp.terminate(nil); return
        }
        let agent = NotificationRestoreAgent(parentPID: parent, session: session)
        active = agent
        agent.start()
    }

    private func start() {
        var enabled: Int32 = 1
        guard setsockopt(STDOUT_FILENO, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0,
              NotificationRecoverySocket.makeNonBlocking(STDIN_FILENO), NotificationRecoverySocket.makeNonBlocking(STDOUT_FILENO) else {
            NSApp.terminate(nil); return
        }
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            guard let data = NotificationRecoverySocket.read(from: handle.fileDescriptor) else { return }
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        reply(NotificationRecoveryMessage(kind: "ready", success: true))
    }

    private func receive(_ data: Data) {
        guard stoppingAt == nil else { return }
        guard !data.isEmpty else { beginStop(); return }
        // 晚到的心跳不能让已经过期的接管重新生效。
        guard !NotificationRecoveryLeasePolicy.expired(lastHeartbeat: lastHeartbeat, now: ProcessInfo.processInfo.systemUptime,
                                                       parentAlive: kill(parentPID, 0) == 0) else { beginStop(); return }
        do {
            for message in try buffer.append(data) {
                switch message.kind {
                case "heartbeat":
                    lastHeartbeat = ProcessInfo.processInfo.systemUptime
                    reply(NotificationRecoveryMessage(kind: "alive", success: true))
                case "park":
                    guard stoppingAt == nil, let target = message.target else { beginStop(); return }
                    let lease = leases[target] ?? NotificationRecoveryAX.lease(target)
                    guard let lease else { reply(NotificationRecoveryMessage(kind: "park", requestID: message.requestID, success: false)); continue }
                    guard !NotificationRecoveryLeasePolicy.expired(lastHeartbeat: lastHeartbeat, now: ProcessInfo.processInfo.systemUptime, parentAlive: kill(parentPID, 0) == 0) else { beginStop(); return }
                    leases[target] = lease
                    // 原坐标必须先落盘，再执行外部窗口移动。
                    try journal.write(Array(leases.values))
                    let parked = NotificationRecoveryAX.park(lease)
                    if !parked { _ = restore() }
                    reply(NotificationRecoveryMessage(kind: "park", requestID: message.requestID, lease: parked ? lease : nil, success: parked))
                case "restore": reply(NotificationRecoveryMessage(kind: "restore", requestID: message.requestID, success: restore()))
                case "stop":
                    let success = restore()
                    reply(NotificationRecoveryMessage(kind: "stop", requestID: message.requestID, success: success))
                    beginStop()
                default: beginStop()
                }
            }
        } catch { reply(NotificationRecoveryMessage(kind: "failure", success: false)); beginStop() }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if stoppingAt == nil,
           NotificationRecoveryLeasePolicy.expired(lastHeartbeat: lastHeartbeat, now: now, parentAlive: kill(parentPID, 0) == 0) {
            beginStop()
        }
    }

    private func beginStop() {
        guard stoppingAt == nil else { return }
        stoppingAt = ProcessInfo.processInfo.systemUptime
        FileHandle.standardInput.readabilityHandler = nil
        timer?.invalidate()
        retryRestore()
    }

    private func retryRestore() {
        if restore() {
            timer?.invalidate()
            NSApp.terminate(nil)
            return
        }
        // 主程序已退出或卡住时，看护仍保留恢复责任；失败日志不能代替实际复位。
        restoreFailures = min(restoreFailures + 1, 4)
        let delay = NotificationRecoveryLeasePolicy.retryDelay(failures: restoreFailures)
        let retry = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryRestore() }
        }
        timer = retry
        RunLoop.main.add(retry, forMode: .common)
    }

    private func restore() -> Bool {
        leases = leases.filter { NotificationRecoveryAX.restore($0.value) == .failed }
        do {
            if leases.isEmpty { try journal.remove() }
            else { try journal.write(Array(leases.values)) }
        } catch { return false }
        return leases.isEmpty
    }

    private func reply(_ message: NotificationRecoveryMessage) {
        do {
            guard NotificationRecoverySocket.write(try NotificationRecoveryLineBuffer.encode(message), to: STDOUT_FILENO) else { beginStop(); return }
        }
        catch { beginStop() }
    }
}
#endif
