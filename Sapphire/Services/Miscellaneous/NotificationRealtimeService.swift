import AppKit
import ApplicationServices
import Combine
import OSLog

enum NotificationRealtimeStatus: Equatable {
    case disabled, starting, active, accessibilityRequired, recoveryUnavailable, nativeFallback, restoreFailed, nativePreserved

    var message: String {
        switch self {
        case .disabled: return "Realtime takeover is off."
        case .starting: return "Preparing notification recovery before takeover…"
        case .active: return "Realtime takeover is ready. System Focus and screen-sharing silence still apply."
        case .accessibilityRequired: return "Allow Accessibility for Sapphire before enabling realtime takeover."
        case .recoveryUnavailable: return "Recovery is unavailable. Native notifications are preserved."
        case .nativeFallback: return "Takeover stopped and native notifications were restored. Retry when ready."
        case .restoreFailed: return "Native restoration is incomplete. Keep Sapphire open and retry restoration."
        case .nativePreserved: return "Some banners remain native because their source or layout could not be verified."
        }
    }
}

/// 仅在来源、内容和恢复看护均明确时移动系统横幅；任何不确定状态回退原生。
@MainActor
final class NotificationRealtimeService: ObservableObject {
    @Published private(set) var status: NotificationRealtimeStatus = .disabled
    var onMessages: (([NotificationRealtimeMessage], Date) -> Void)?
    var onNativeRestored: (() -> Void)?
    var shouldManageApplication: ((String) -> Bool)?

    private let recovery = NotificationWindowRecovery()
    private let queue = DispatchQueue(label: "com.sapphire.notification-realtime", qos: .userInitiated)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotificationRealtime")
    private var subscriptions = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var observer: AXObserverHandle?
    private var observedPID: pid_t?
    private var reading = false
    private var restoring = false
    private var lifecycle: Task<Void, Never>?
    private var leasedTargets = Set<NotificationWindowTarget>()
    private var pendingParkTargets = Set<NotificationWindowTarget>()
    private var generation = UUID()
    private var enabled = false
    private var knownApplications: [NotificationKnownApplication] = []
    private var displayed: [NotificationWindowTarget: [NotificationRealtimeMessage]] = [:]
    private var lastNotificationCenterLaunch: Date?

    init() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restoreForContextChange() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AccessibilityTrustMonitor.trustDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard !AccessibilityPermission.isProcessTrusted else { return }
                self?.failToNative()
            }
            .store(in: &subscriptions)
    }

    func start() async {
        guard !enabled else { return }
        enabled = true
        generation = UUID()
        let session = generation
        status = .starting
        let previous = lifecycle
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.enabled, self.generation == session else { return }
            guard AccessibilityPermission.isProcessTrusted else {
                self.enabled = false
                self.status = .accessibilityRequired
                return
            }
            guard await self.recovery.start() else {
                guard self.generation == session else { return }
                self.enabled = false
                self.status = .recoveryUnavailable
                return
            }
            // 所有生命周期操作串行；此旧 start 清理完成前，新会话不会使用看护。
            guard self.enabled, self.generation == session else { await self.recovery.stop(); return }
            self.recovery.onFailure = { [weak self] in self?.failToNative() }
            self.knownApplications = Self.applicationCatalog()
            self.status = .active
            self.timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.requestRead() }
            self.requestRead()
        }
        lifecycle = operation
        await operation.value
    }

    func suspend() {
        enabled = false
        restoring = false
        generation = UUID()
        timer?.cancel()
        timer = nil
        observer?.detach()
        observer = nil
        observedPID = nil
    }

    func stop() async { await stop(finalStatus: .disabled) }

    func recoverStaleWindows() {
        if !NotificationWindowRecovery.recoverStaleWindows() { status = .restoreFailed }
    }

    private func stop(finalStatus: NotificationRealtimeStatus) async {
        suspend()
        let session = generation
        let previous = lifecycle
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            self.recovery.onFailure = nil
            await self.recovery.stop()
            if self.recovery.lastRestoreSucceeded {
                self.displayed.removeAll()
                self.leasedTargets.removeAll()
                self.pendingParkTargets.removeAll()
                self.onNativeRestored?()
            }
            guard self.generation == session, !self.enabled else { return }
            self.status = self.recovery.lastRestoreSucceeded ? finalStatus : .restoreFailed
        }
        lifecycle = operation
        await operation.value
    }

    private func failToNative() {
        guard enabled else { return }
        suspend()
        let failedSession = generation
        Task { @MainActor [weak self] in
            guard let self, self.generation == failedSession else { return }
            self.logger.error("Realtime takeover stopped; restoring native notification windows")
            await self.stop(finalStatus: .nativeFallback)
        }
    }

    private func restoreForContextChange() {
        guard enabled else { return }
        generation = UUID()
        let session = generation
        restoring = true
        let previous = lifecycle
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.enabled, self.generation == session else { return }
            await self.restoreLeases(notify: true)
            if self.generation == session { self.restoring = false }
        }
        lifecycle = operation
    }

    private func restoreLeases(notify: Bool) async {
        if !leasedTargets.isEmpty || !pendingParkTargets.isEmpty {
            await recovery.restoreAll()
            guard recovery.lastRestoreSucceeded else { failToNative(); return }
            leasedTargets.removeAll()
            pendingParkTargets.removeAll()
        }
        displayed.removeAll()
        if notify { onNativeRestored?() }
    }

    private func requestRead() {
        guard enabled, !reading, !restoring, recovery.isReady else { return }
        guard let center = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) else {
            failToNative()
            return
        }
        if observedPID != center.processIdentifier {
            observer?.detach()
            observedPID = center.processIdentifier
            let observer = AXObserverHandle(pid: center.processIdentifier) { [weak self] _, _ in
                Task { @MainActor in self?.requestRead() }
            }
            observer?.observe([kAXWindowCreatedNotification as String, kAXCreatedNotification as String,
                               kAXLayoutChangedNotification as String, kAXUIElementDestroyedNotification as String],
                              on: AX.application(pid: center.processIdentifier))
            observer?.attach()
            self.observer = observer
        }
        if lastNotificationCenterLaunch != center.launchDate {
            lastNotificationCenterLaunch = center.launchDate
            knownApplications = Self.applicationCatalog()
        }
        let focused = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.notificationcenterui"
        let pid = center.processIdentifier
        let session = generation
        reading = true
        queue.async { [weak self] in
            let captured = Self.capture(pid: pid, centerFocused: focused)
            Task { @MainActor in
                guard let self else { return }
                defer { self.reading = false }
                guard self.enabled, self.generation == session else { return }
                await self.consume(captured, session: session)
            }
        }
    }

    private func consume(_ captured: CaptureBatch, session: UUID) async {
        guard captured.succeeded else { failToNative(); return }
        let windows = captured.windows
        if windows.isEmpty { await restoreLeases(notify: false); return }
        let visible = Set(windows.map(\.target))
        displayed = displayed.filter { visible.contains($0.key) }
        guard !windows.contains(where: { $0.isHistory || !$0.complete }) else {
            await restoreLeases(notify: true)
            if enabled, generation == session, status != .nativePreserved { status = .nativePreserved }
            return
        }
        let parsedWindows = windows.map { ($0, NotificationBannerParser.parse(root: $0.tree, knownApplications: knownApplications)) }
        guard parsedWindows.allSatisfy({ $0.1.canHide && $0.1.messages.allSatisfy { shouldManageApplication?($0.appIdentifier) == true } }) else {
            // 整批先校验，避免先隐藏一块屏幕后才发现另一块含未知消息。
            await restoreLeases(notify: true)
            if enabled, generation == session, status != .nativePreserved { status = .nativePreserved }
            return
        }
        for (captured, parsed) in parsedWindows {
            guard enabled, !restoring, generation == session, recovery.isReady else { return }
            pendingParkTargets.insert(captured.target)
            let parked = await recovery.park(captured.target)
            guard enabled, generation == session else { return }
            pendingParkTargets.remove(captured.target)
            guard parked else { failToNative(); return }
            leasedTargets.insert(captured.target)
            if status != .active { status = .active }
            let previous = displayed[captured.target] ?? []
            let updates = parsed.messages.filter { !previous.contains($0) }
            displayed[captured.target] = parsed.messages
            if !updates.isEmpty { onMessages?(updates, Date()) }
        }
    }

    private struct CapturedWindow {
        let target: NotificationWindowTarget
        let tree: NotificationAXNode
        let complete: Bool
        let isHistory: Bool
    }

    #if DEBUG
    struct DiagnosticWindow {
        let target: NotificationWindowTarget
        let tree: NotificationAXNode
        let frame: CGRect
    }

    nonisolated static func diagnosticWindows() -> [DiagnosticWindow] {
        guard let process = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) else { return [] }
        let batch = capture(pid: process.processIdentifier, centerFocused: false)
        guard batch.succeeded else { return [] }
        let application = AX.application(pid: process.processIdentifier)
        return batch.windows.compactMap { candidate in
            guard let window = AX.elements(kAXWindowsAttribute as String, of: application).first(where: { AX.windowID(of: $0) == candidate.target.windowID }),
                  let frame = AX.windowFrame(of: window) else { return nil }
            return DiagnosticWindow(target: candidate.target, tree: candidate.tree, frame: frame)
        }
    }
    #endif

    private struct CaptureBatch {
        var windows: [CapturedWindow] = []
        var succeeded = true
    }

    nonisolated private static func capture(pid: pid_t, centerFocused: Bool) -> CaptureBatch {
        let application = AX.application(pid: pid)
        AX.setMessagingTimeout(0.1, on: application)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement] else { return CaptureBatch(succeeded: false) }
        var results: [CapturedWindow] = []
        let end = Date().addingTimeInterval(0.7)
        for window in windows.prefix(16) {
            guard Date() < end else { return CaptureBatch(succeeded: false) }
            AX.setMessagingTimeout(0.1, on: window)
            guard AX.role(of: window) == "AXWindow", AX.subrole(of: window) == "AXSystemDialog",
                  let id = AX.windowID(of: window) else { continue }
            var visited = Set<CFHashCode>()
            var complete = true
            let tree = snapshot(window, depth: 0, visited: &visited, end: end, complete: &complete)
            let history = centerFocused || AX.bool(kAXFocusedAttribute as String, of: window) == true || containsHistory(tree)
            results.append(CapturedWindow(target: NotificationWindowTarget(pid: pid, windowID: id), tree: tree,
                                          complete: complete, isHistory: history))
        }
        return CaptureBatch(windows: results, succeeded: windows.count <= 16)
    }

    nonisolated private static func snapshot(_ element: AXUIElement, depth: Int, visited: inout Set<CFHashCode>, end: Date, complete: inout Bool) -> NotificationAXNode {
        guard depth < 14, visited.count < 800, Date() < end else {
            complete = false
            return NotificationAXNode(role: "incomplete")
        }
        guard visited.insert(CFHash(element)).inserted else { return NotificationAXNode(role: "duplicate") }
        AX.setMessagingTimeout(0.08, on: element)
        let role = AX.role(of: element) ?? ""
        var description = AX.string(kAXDescriptionAttribute as String, of: element) ?? ""
        if description.isEmpty { description = (AX.rawValue("AXAttributedDescription", of: element) as? NSAttributedString)?.string ?? "" }
        var childIDs = Set<CFHashCode>()
        let candidates = AX.children(of: element) + AX.elements(kAXContentsAttribute as String, of: element)
            + AX.elements("AXVisibleChildren", of: element)
        var children = candidates.filter { childIDs.insert(CFHash($0)).inserted }
        if children.isEmpty { children = AX.elements("AXChildrenInNavigationOrder", of: element) }
        let nodes = children.prefix(80).map { snapshot($0, depth: depth + 1, visited: &visited, end: end, complete: &complete) }
        if children.count > 80 { complete = false }
        return NotificationAXNode(role: role, subrole: AX.subrole(of: element) ?? "",
                                  identifier: AX.string(kAXIdentifierAttribute as String, of: element) ?? "",
                                  title: AX.string(kAXTitleAttribute as String, of: element) ?? "",
                                  description: description, value: AX.string(kAXValueAttribute as String, of: element)
                                      ?? (AX.rawValue(kAXValueAttribute as String, of: element) as? NSAttributedString)?.string ?? "",
                                  children: nodes)
    }

    nonisolated private static func containsHistory(_ node: NotificationAXNode) -> Bool {
        node.role == "AXScrollArea" || node.identifier.hasPrefix("widget-local:")
            || node.children.contains(where: containsHistory)
    }

    private static func applicationCatalog() -> [NotificationKnownApplication] {
        var aliases: [String: Set<String>] = [:]
        for app in InstalledApplications.namesAndBundleIDs() { aliases[app.bundleID, default: []].insert(app.name) }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            if let name = app.localizedName { aliases[id, default: []].insert(name) }
            if let url = app.bundleURL {
                aliases[id, default: []].insert(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            }
        }
        if let id = Bundle.main.bundleIdentifier { aliases[id, default: []].insert("Sapphire") }
        return aliases.map { NotificationKnownApplication(identifier: $0.key, displayNames: Array($0.value)) }
    }
}
