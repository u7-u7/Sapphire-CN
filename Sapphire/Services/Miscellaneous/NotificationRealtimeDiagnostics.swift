#if DEBUG && CN11_NOTIFICATION_DIAGNOSTICS
import AppKit
import UserNotifications
import Darwin

/// 本地受控验收入口。只保存测试事件与窗口元数据，正常启动不会进入。
@MainActor
enum NotificationRealtimeDiagnostics {
    static func runIfRequested() -> Bool {
        // 从 LaunchServices 启动才能沿用本应用的 TCC 归属；直接由终端启动会归到终端授权。
        // 单次本机测试请求过期即丢弃，避免影响下次日常启动。
        let requestURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SapphireCN11TestLaunch-\(getuid()).json")
        var launchRequest: [String: String]?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: requestURL.path),
           attributes[.type] as? FileAttributeType == .typeRegular,
           (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
           let modified = attributes[.modificationDate] as? Date,
           abs(modified.timeIntervalSinceNow) < 60,
           (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 4096 {
            launchRequest = (try? Data(contentsOf: requestURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            try? FileManager.default.removeItem(at: requestURL)
        }
        guard CommandLine.arguments.contains("--cn11-notification-test") || launchRequest != nil else { return false }
        func argument(_ key: String) -> String? {
            if let value = launchRequest?[key] { return value }
            guard let index = CommandLine.arguments.firstIndex(of: key), CommandLine.arguments.indices.contains(index + 1) else { return nil }
            return CommandLine.arguments[index + 1]
        }
        guard let raw = argument("--test-session"), let session = UUID(uuidString: raw) else { return true }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = NotificationDiagnosticHost(session: session, scenario: argument("--scenario") ?? "inspect")
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        return true
    }
}

private struct NotificationDiagnosticTarget: Codable {
    let target: NotificationWindowTarget
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let requestIdentifier: String
}

@MainActor
private final class NotificationDiagnosticHost: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let session: UUID
    private let scenario: String
    private let directory: URL
    private let marker = "CN11-" + UUID().uuidString
    private let requestID = "sapphire-cn11-test-" + UUID().uuidString
    private let recovery = NotificationWindowRecovery()
    private let realtime = NotificationRealtimeService()
    private let queue = DispatchQueue(label: "com.sapphire.notification-diagnostics")
    private var timer: Timer?
    private var scanning = false
    private var found = false
    private var exported = false
    private var sentAt: Date?
    private var finishing = false
    private var inheritedRequestIdentifier: String?

    init(session: UUID, scenario: String) {
        self.session = session
        self.scenario = scenario
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SapphireCN11SelfTests/\(session.uuidString)", isDirectory: true)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { NSApp.terminate(nil); return }
        if scenario == "verify" || scenario == "recover-stale" { verify(); return }
        record("started", ["pid": Int(getpid()), "scenario": scenario, "trusted": AccessibilityPermission.isProcessTrusted])
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.record("permissions", ["authorization": settings.authorizationStatus.rawValue, "alertStyle": settings.alertStyle.rawValue])
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    self.record("failed", ["reason": "notification permission missing"]); self.finish(); return
                }
                await self.prepare()
            }
        }
    }

    private func prepare() async {
        if scenario == "capture" {
            realtime.shouldManageApplication = { $0 == Bundle.main.bundleIdentifier }
            realtime.onMessages = { [weak self] messages, date in
                guard let self else { return }
                let own = messages.filter { $0.body.contains(self.marker) }
                if !own.isEmpty { self.record("realtime_message", ["count": own.count, "age": self.sentAt.map { date.timeIntervalSince($0) } ?? -1]) }
            }
            await realtime.start()
            record("realtime_ready", ["ready": realtime.status == .active])
        } else if scenario != "inspect" {
            guard await recovery.start() else { record("failed", ["reason": "recovery unavailable"]); finish(); return }
            record("recovery_ready", ["agentPID": Int(recovery.agentProcessIdentifier ?? 0)])
        }
        sentAt = Date()
        let content = UNMutableNotificationContent()
        content.title = "Sapphire CN11 本机验证"
        content.body = marker
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: requestID, content: content, trigger: nil)) { error in
            Task { @MainActor in self.record("submitted", ["success": error == nil]) }
        }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readControlledWindow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.finish() }
    }

    private func readControlledWindow() {
        guard !scanning, !found else { return }
        scanning = true
        let marker = self.marker
        queue.async { [weak self] in
            let windows = NotificationRealtimeService.diagnosticWindows()
            let own = windows.first { Self.contains($0.tree, marker: marker) }
            Task { @MainActor in
                guard let self else { return }
                defer { self.scanning = false }
                guard let own else { return }
                if !self.exported {
                    self.exported = true
                    let sanitized = Self.sanitize(own.tree, marker: marker)
                    do { try JSONEncoder().encode(sanitized).write(to: self.directory.appendingPathComponent("snapshot.json"), options: .atomic) }
                    catch { self.record("snapshot_error") }
                    self.record("snapshot", ["age": self.sentAt.map { Date().timeIntervalSince($0) } ?? -1])
                }
                if self.scenario == "inspect" || self.scenario == "capture" { return }
                self.found = true
                let metadata = NotificationDiagnosticTarget(target: own.target, x: own.frame.minX, y: own.frame.minY,
                                                            width: own.frame.width, height: own.frame.height,
                                                            requestIdentifier: self.requestID)
                do { try JSONEncoder().encode(metadata).write(to: self.directory.appendingPathComponent("target.json"), options: .atomic) }
                catch { self.record("failed", ["reason": "target metadata write failed"]); self.finish(); return }
                let parked = await self.recovery.park(own.target)
                self.record("parked", ["success": parked])
                guard parked else { self.finish(); return }
                await self.exerciseFailure()
            }
        }
    }

    private func exerciseFailure() async {
        switch scenario {
        case "parent-crash": kill(getpid(), SIGKILL)
        case "parent-freeze":
            record("freezing")
            raise(SIGSTOP)
            record("resumed")
            finish()
        case "watchdog-crash":
            guard let pid = recovery.agentProcessIdentifier else { record("failed"); finish(); return }
            kill(pid, SIGKILL)
            try? await Task.sleep(for: .seconds(1))
            verifyPosition()
            finish()
        case "both-crash":
            if let pid = recovery.agentProcessIdentifier { kill(pid, SIGKILL) }
            kill(getpid(), SIGKILL)
        default:
            await recovery.stop()
            verifyPosition()
            finish()
        }
    }

    private func verify() {
        if scenario == "recover-stale" { record("stale_recovery", ["success": NotificationWindowRecovery.recoverStaleWindows()]) }
        verifyPosition()
        finish()
    }

    private func verifyPosition() {
        do {
            let target = try JSONDecoder().decode(NotificationDiagnosticTarget.self, from: Data(contentsOf: directory.appendingPathComponent("target.json")))
            inheritedRequestIdentifier = target.requestIdentifier
            let application = AX.application(pid: target.target.pid)
            let window = AX.elements(kAXWindowsAttribute as String, of: application).first { AX.windowID(of: $0) == target.target.windowID }
            guard let window, let actual = AX.windowFrame(of: window) else { record("position", ["restored": false, "gone": true]); return }
            record("position", ["restored": abs(actual.minX - target.x) < 2 && abs(actual.minY - target.y) < 2, "gone": false])
        } catch { record("position", ["restored": false, "error": true]) }
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        timer?.invalidate()
        timer = nil
        Task { @MainActor in
            await realtime.stop()
            await recovery.stop()
            let requests = [requestID] + (inheritedRequestIdentifier.map { [$0] } ?? [])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requests)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests)
            record("finished")
            NSApp.terminate(nil)
        }
    }

    private func record(_ event: String, _ fields: [String: Any] = [:]) {
        var row = fields
        row["event"] = event
        row["time"] = Date().timeIntervalSince1970
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10)
        let file = directory.appendingPathComponent("\(scenario).jsonl")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o600]) }
        do {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } catch { print("[CN11Diagnostic] Test metadata could not be written") }
    }

    nonisolated private static func contains(_ node: NotificationAXNode, marker: String) -> Bool {
        [node.title, node.description, node.value].contains { $0.contains(marker) } || node.children.contains { contains($0, marker: marker) }
    }

    nonisolated private static func sanitize(_ node: NotificationAXNode, marker: String) -> NotificationAXNode {
        let allowed = ["Sapphire", "Sapphire CN11 本机验证", marker, "刚刚", "现在", "now", "关闭", "Close", "选项", "Options"]
        func scrub(_ value: String) -> String {
            if value.isEmpty || allowed.contains(value) { return value }
            let tokens = allowed.filter { value.contains($0) }
            return tokens.isEmpty ? "<redacted>" : tokens.joined(separator: " | ")
        }
        let id = node.identifier.contains("com.cshariq.sapphire") || node.identifier.count < 80 && ["app-name", "app-icon", "source-name", "time-label", "timestamp"].contains(where: node.identifier.contains) ? node.identifier : ""
        return NotificationAXNode(role: node.role, subrole: node.subrole, identifier: id,
                                  title: scrub(node.title), description: scrub(node.description), value: scrub(node.value),
                                  children: node.children.map { sanitize($0, marker: marker) })
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list])
    }
}
#endif
