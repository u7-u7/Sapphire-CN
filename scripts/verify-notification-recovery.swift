// Compile together with NotificationWindowRecovery.swift using -D NOTIFICATION_RECOVERY_TESTING.
import Foundation
import Darwin

@main
struct VerifyNotificationRecovery {
    static func main() throws {
        precondition(!NotificationRecoveryLeasePolicy.expired(lastHeartbeat: 100, now: 101.9, parentAlive: true))
        precondition(NotificationRecoveryLeasePolicy.expired(lastHeartbeat: 100, now: 102.1, parentAlive: true), "A frozen parent must lose its hide lease")
        precondition(NotificationRecoveryLeasePolicy.expired(lastHeartbeat: 100, now: 100.1, parentAlive: false), "Parent death immediately requires restoration")
        precondition(NotificationRecoveryLeasePolicy.expired(lastHeartbeat: 100, now: 99, parentAlive: true))
        precondition(NotificationRecoveryLeasePolicy.retryDelay(failures: 1) == 1)
        precondition(NotificationRecoveryLeasePolicy.retryDelay(failures: 2) == 2)
        precondition(NotificationRecoveryLeasePolicy.retryDelay(failures: 4) == 5)
        precondition(NotificationRecoveryLeasePolicy.retryDelay(failures: 100) == 5)
        let ownProcessStart = NotificationRecoveryProcessIdentity.startedAt(getpid())
        precondition(ownProcessStart != nil)
        precondition(NotificationRecoveryProcessIdentity.isAlive(getpid(), startedAt: ownProcessStart))
        precondition(!NotificationRecoveryProcessIdentity.isAlive(getpid(), startedAt: (ownProcessStart ?? 0) - 100), "PID start time must distinguish a reused owner PID")
        precondition(NotificationRecoveryProcessIdentity.executable(getpid()) != nil)
        let mainPath = "/Applications/Sapphire.app/Contents/MacOS/Sapphire"
        let helperPath = "/Applications/Sapphire.app/Contents/MacOS/SapphireNotificationRecovery"
        precondition(NotificationRecoveryPathPolicy.validPair(parentPath: mainPath, agentPath: helperPath))
        precondition(!NotificationRecoveryPathPolicy.validPair(parentPath: mainPath, agentPath: mainPath), "Same-name child must be rejected")
        precondition(!NotificationRecoveryPathPolicy.validPair(parentPath: mainPath, agentPath: "/tmp/SapphireNotificationRecovery"))
        precondition(!NotificationRecoveryPathPolicy.validPair(parentPath: mainPath, agentPath: "/Applications/Other.app/Contents/MacOS/SapphireNotificationRecovery"))
        precondition(NotificationRecoveryPathPolicy.companion(for: URL(fileURLWithPath: "/tmp/Sapphire")) == nil)
        let signer = NotificationRecoverySigningIdentity(identifier: "com.cshariq.sapphire", team: "EXAMPLE")
        precondition(signer.matches(signer))
        precondition(!signer.matches(NotificationRecoverySigningIdentity(identifier: "other", team: "EXAMPLE")))
        precondition(!signer.matches(NotificationRecoverySigningIdentity(identifier: "com.cshariq.sapphire", team: "OTHER")))
        precondition(!NotificationRecoverySigningIdentity(identifier: "", team: "").matches(NotificationRecoverySigningIdentity(identifier: "", team: "")))
        let target = NotificationWindowTarget(pid: 123, windowID: 456)
        let startedAt = Date().addingTimeInterval(-100).timeIntervalSince1970
        let lease = NotificationWindowLease(target: target, processStartedAt: startedAt,
                                            originalX: 0, originalY: 0, width: 1470, height: 956,
                                            parkedX: 32000, parkedY: 32000)
        precondition(lease.isSane)
        precondition(lease.matches(startedAt: startedAt, x: 32000, y: 32000))
        precondition(!lease.matches(startedAt: startedAt + 10, x: 32000, y: 32000), "PID reuse must not match")
        precondition(!lease.matches(startedAt: startedAt, x: 0, y: 0), "A user-restored window must not be moved again")
        let mainDisplay = CGRect(x: 0, y: 0, width: 1200, height: 800)
        precondition(lease.restorationOrigin(displays: [mainDisplay], mainDisplay: mainDisplay) == .zero)
        let detached = NotificationWindowLease(target: target, processStartedAt: startedAt, originalX: 1800, originalY: 0,
                                               width: 1470, height: 956, parkedX: 32000, parkedY: 32000)
        precondition(detached.restorationOrigin(displays: [mainDisplay], mainDisplay: mainDisplay) == .zero, "Disconnected display origins fall back to current main screen")
        let bad = NotificationWindowLease(target: target, processStartedAt: startedAt, originalX: 32000, originalY: 0,
                                          width: 1470, height: 956, parkedX: 32000, parkedY: 32000)
        precondition(!bad.isSane)

        var buffer = NotificationRecoveryLineBuffer()
        let ready = try NotificationRecoveryLineBuffer.encode(NotificationRecoveryMessage(kind: "ready", success: true))
        let split = ready.count / 2
        let partial = try buffer.append(Data(ready.prefix(split)))
        precondition(partial.isEmpty)
        let finished = try buffer.append(Data(ready.dropFirst(split)))
        precondition(finished.count == 1 && finished[0].kind == "ready" && finished[0].success == true)
        let id = UUID()
        let park = try NotificationRecoveryLineBuffer.encode(NotificationRecoveryMessage(kind: "park", requestID: id, target: target))
        let restore = try NotificationRecoveryLineBuffer.encode(NotificationRecoveryMessage(kind: "restore", requestID: UUID()))
        let merged = try buffer.append(park + restore)
        precondition(merged.count == 2 && merged[0].target == target && merged[0].requestID == id)
        do { _ = try buffer.append(Data(repeating: 65, count: 65537)); preconditionFailure("Oversized IPC frame must fail") }
        catch { }
        var malformed = NotificationRecoveryLineBuffer()
        do { _ = try malformed.append(Data("invalid\n".utf8)); preconditionFailure("Malformed command must fail closed") }
        catch { }
        verifySocketTransport()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notification-recovery-verify-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = NotificationRecoveryJournal(url: directory.appendingPathComponent("lease-test.json"))
        try journal.write([lease])
        let decoded = try journal.read()
        precondition(decoded == [lease])
        let firstOwner = try journal.readEnvelope().ownerPID
        try journal.write([lease])
        let persistedOwner = try journal.readEnvelope().ownerPID
        precondition(persistedOwner == firstOwner)
        let permissions = try FileManager.default.attributesOfItem(atPath: journal.url.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        try journal.write([bad])
        do { _ = try journal.read(); preconditionFailure("Invalid restoration coordinates must be rejected") }
        catch { }
        try journal.remove()
        precondition(!FileManager.default.fileExists(atPath: journal.url.path))
        print("PASS: lease expiry and parent death, recovery geometry guards, screen removal, process epochs, framed IPC, real socket backpressure/EAGAIN/EOF/no SIGPIPE, corrupt input, journal owner preservation and private permissions")
    }

    private static func verifySocketTransport() {
        // 独立队列限时，防止阻塞写回归把测试自身挂住。
        let deadline = DispatchSource.makeTimerSource(queue: .global())
        deadline.schedule(deadline: .now() + 2)
        deadline.setEventHandler {
            fputs("FAIL: recovery socket blocked beyond its deadline\n", stderr)
            _exit(1)
        }
        deadline.resume()
        defer { deadline.cancel() }

        var descriptors: [Int32] = [0, 0]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer {
            close(descriptors[0])
            if descriptors[1] >= 0 { close(descriptors[1]) }
        }
        var enabled: Int32 = 1
        precondition(setsockopt(descriptors[0], SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0)
        precondition(NotificationRecoverySocket.makeNonBlocking(descriptors[1]))
        precondition(NotificationRecoverySocket.read(from: descriptors[1]) == nil, "EAGAIN must not be mistaken for EOF")
        let hello = Data("ready\n".utf8)
        precondition(NotificationRecoverySocket.write(hello, to: descriptors[0]))
        precondition(NotificationRecoverySocket.read(from: descriptors[1]) == hello)

        let payload = Data(repeating: 1, count: 16384)
        let startedAt = ProcessInfo.processInfo.systemUptime
        var rejected = false
        for _ in 0..<10000 {
            if !NotificationRecoverySocket.write(payload, to: descriptors[0]) { rejected = true; break }
        }
        precondition(rejected, "An unread socket must eventually report backpressure")
        precondition(ProcessInfo.processInfo.systemUptime - startedAt < 1, "Backpressure must fail immediately rather than block restoration")
        close(descriptors[1]); descriptors[1] = -1
        precondition(NotificationRecoverySocket.read(from: descriptors[0]) == Data(), "Peer closure must produce EOF")
        precondition(!NotificationRecoverySocket.write(payload, to: descriptors[0]), "A closed peer must fail without terminating on SIGPIPE")
    }
}
