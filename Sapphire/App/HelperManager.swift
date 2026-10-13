//
//  HelperManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import ServiceManagement
import AppKit
import SwiftUI
import OSLog

private let helperLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "HelperManager")
private let sapphireHelperPlistName = "com.shariq.sapphireHelper.plist"

// MARK: - Error codes

enum HelperIssue: Equatable {
    case spawnFailed
    case needsApproval
    case notFound

    var code: String {
        switch self {
        case .spawnFailed: return "SAP-H1"
        case .needsApproval: return "SAP-H2"
        case .notFound: return "SAP-H3"
        }
    }

    var title: String {
        switch self {
        case .spawnFailed: return "Helper connection unavailable"
        case .needsApproval: return "Login Items approval required"
        case .notFound: return "Helper registration missing"
        }
    }

    var shortSummary: String {
        switch self {
        case .spawnFailed:
            return "Permission is granted, but Sapphire cannot connect to the helper."
        case .needsApproval:
            return "Turn on Sapphire and Sapphire Helper in Login Items."
        case .notFound:
            return "macOS lost the helper (status 3). Reset the helper; Sapphire will relaunch if it stays stuck."
        }
    }

    var instructions: String {
        switch self {
        case .notFound:
            return """
            Error code: SAP-H3

            macOS can't find the helper.

            Do fix this:
            1. Click “Reset Helper” below. Sapphire will unregister the helper with SMAppService and register it again.
            2. If the helper still does not start, Sapphire will relaunch itself — or click “Relaunch Sapphire”.
            3. When Sapphire opens, click Install if asked.
            4. In System Settings → General → Login Items, enable Sapphire Helper under Allow in the Background.

            Try Reset Helper first. Only relaunch the app if the helper is still stuck after that.
            """
        case .needsApproval:
            return """
            Error code: SAP-H2

            macOS registered the helper but is waiting for your permission (SMAppService status 2).

            Do this:
            1. Click “Open Login Items” below.
            2. Under Allow in the Background, turn on Sapphire.
            3. Authenticate if macOS asks for your password.
            4. Return to Sapphire and click Install / Activate.
            """
        case .spawnFailed:
            return """
            Error code: SAP-H1

            Login Items permission is already granted (status 1), but Sapphire cannot connect to the helper. The helper may still be starting or checking the app’s signature.

            Click “Reset Helper” below. Sapphire will unregister the helper and register it again, then relaunch if the helper is still having issues.
            """
        }
    }
}

struct HelperStatusBanner: View {
    @ObservedObject var helperManager: HelperManager

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: helperManager.bannerSymbol)
                .font(.title2)
                .foregroundColor(helperManager.bannerColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(helperManager.bannerTitle)
                        .font(.headline)
                    if let issue = helperManager.lastIssue {
                        Text(issue.code)
                            .font(.caption.weight(.semibold).monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(helperManager.bannerColor.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(helperManager.bannerSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let issue = helperManager.lastIssue {
                    Button("Instructions") {
                        HelperAlertPresenter.present(issue)
                    }
                    .buttonStyle(.bordered)
                }

                if !helperManager.isRunning {
                    if helperManager.status == .enabled {
                        Button(helperManager.isResettingHelper ? "Resetting…" : "Reset Helper") {
                            helperManager.resetOwnBackgroundActivity()
                        }
                        .disabled(helperManager.isResettingHelper)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else if helperManager.status == .notFound {
                        Button(helperManager.isResettingHelper ? "Resetting…" : "Reset Helper") {
                            helperManager.resetOwnBackgroundActivity()
                        }
                        .disabled(helperManager.isResettingHelper)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        Button("Relaunch") {
                            HelperManager.relaunchApp()
                        }
                        .buttonStyle(.bordered)
                    } else if helperManager.status == .requiresApproval {
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                            helperManager.beginInstallation()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else if helperManager.status != .enabled {
                        Button("Install") {
                            helperManager.beginInstallation()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                    }
                }
            }
        }
    }
}

@MainActor
class HelperManager: ObservableObject {
    static let shared = HelperManager()

    let helperToolIdentifier = "com.shariq.sapphireHelper"

    @Published var status: SMAppService.Status = .notRegistered
    @Published var isRunning: Bool = false
    @Published var lastIssue: HelperIssue?
    @Published var isResettingHelper = false

    private var isRegistering = false
    private var isReconcilingHelper = false
    private var reconciliationGeneration = 0
    private var healthCheckInFlight = false
    private var connectionObservers: [NSObjectProtocol] = []
    private var lastHealthCheck = Date.distantPast
    private let healthCheckMinimumInterval: TimeInterval = 5
    private var lastRegisterAttempt: Date?
    private var consecutiveMissedPings = 0
    private var presentedIssuesThisSession = Set<String>()
    private let registerCooldown: TimeInterval = 8

    private static var bundledPlistURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(sapphireHelperPlistName, isDirectory: false)
    }

    var bannerTitle: String {
        if isRunning { return "Helper Active" }
        return lastIssue?.title ?? "Helper Not Installed"
    }

    var bannerSubtitle: String {
        if isRunning {
            return "Privileged helper is running."
        }
        return lastIssue?.shortSummary ?? "Install the helper to enable battery management and system integrations."
    }

    var bannerSymbol: String {
        if isRunning { return "checkmark.circle.fill" }
        switch lastIssue {
        case .spawnFailed: return "exclamationmark.octagon.fill"
        case .needsApproval: return "exclamationmark.triangle.fill"
        case .notFound: return "arrow.triangle.2.circlepath.circle.fill"
        case nil: return "xmark.circle.fill"
        }
    }

    var bannerColor: Color {
        if isRunning { return .green }
        switch lastIssue {
        case .spawnFailed: return .red
        case .needsApproval: return .yellow
        case .notFound: return .orange
        case nil: return .red
        }
    }

    private init() {
        let plistURL = Self.bundledPlistURL
        let plistExists = FileManager.default.fileExists(atPath: plistURL.path)
        helperLogger.info("[HelperManager] Initialized bundle=\(Bundle.main.bundlePath, privacy: .public) plist=\(plistURL.path, privacy: .public) exists=\(plistExists)")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatus),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        let center = NotificationCenter.default
        connectionObservers = [
            center.addObserver(forName: .sapphireHelperConnectionLost, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.helperConnectionDidFail() }
            },
            center.addObserver(forName: .sapphireHelperConnectionRestored, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.helperConnectionDidRecover() }
            }
        ]

        Task { _ = await refreshStatus() }
    }

    deinit {
        connectionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func helperConnectionDidFail() {
        consecutiveMissedPings = 3
        isRunning = false
        refreshIssue()
    }

    private func helperConnectionDidRecover() {
        consecutiveMissedPings = 0
        isRunning = true
        refreshIssue()
    }

    nonisolated static func relaunchApp() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"\(path)\""]
        try? task.run()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc func updateStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.refreshStatus()
            if self.status == .enabled {
                self.checkIfRunning(force: false)
            }
        }
    }

    private func bundledPlistIsReadable() -> Bool {
        let url = Self.bundledPlistURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            helperLogger.error("[HelperManager] Bundled LaunchDaemon plist is missing at \(url.path, privacy: .public)")
            return false
        }
        guard let data = try? Data(contentsOf: url),
              (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
            helperLogger.error("[HelperManager] Bundled LaunchDaemon plist is not a readable property list at \(url.path, privacy: .public)")
            return false
        }
        return true
    }

    private func refreshStatus() async -> SMAppService.Status {
        guard bundledPlistIsReadable() else {
            applyStatus(.notFound)
            return .notFound
        }
        let newStatus = await Self.fetchDaemonStatus()
        applyStatus(newStatus)
        return newStatus
    }

    private func applyStatus(_ newStatus: SMAppService.Status) {
        if status != newStatus {
            helperLogger.info("[HelperManager] Status changed: \(String(describing: self.status)) -> \(String(describing: newStatus))")
            status = newStatus
        }
        refreshIssue()
    }

    nonisolated private static func fetchDaemonStatus() async -> SMAppService.Status {
        await Task.detached(priority: .utility) {
            SMAppService.daemon(plistName: sapphireHelperPlistName).status
        }.value
    }

    nonisolated private static func registerDaemon() async -> String? {
        await Task.detached(priority: .utility) {
            let service = SMAppService.daemon(plistName: sapphireHelperPlistName)
            do {
                try service.register()
                return nil
            } catch {
                let status = service.status
                if status == .enabled || status == .requiresApproval {
                    return nil
                }
                return error.localizedDescription
            }
        }.value
    }

    nonisolated private static func unregisterDaemon() async -> String? {
        await Task.detached(priority: .utility) {
            let service = SMAppService.daemon(plistName: sapphireHelperPlistName)
            do {
                try service.unregister()
                return nil
            } catch {
                let status = service.status
                if status == .notRegistered || status == .notFound {
                    return nil
                }
                return error.localizedDescription
            }
        }.value
    }

    func checkIfRunning(force: Bool = false) {
        guard !isRegistering, !isReconcilingHelper, !healthCheckInFlight else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastHealthCheck) >= healthCheckMinimumInterval else { return }
        healthCheckInFlight = true
        lastHealthCheck = now
        let generation = reconciliationGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard generation == self.reconciliationGeneration else {
                self.healthCheckInFlight = false
                return
            }
            let running = await XPCClient.shared.ping(timeout: 2)
            self.healthCheckInFlight = false
            guard generation == self.reconciliationGeneration else { return }
            helperLogger.info("[HelperManager] Ping result: \(running ? "running" : "NOT running"), current status: \(String(describing: self.status))")
            self.applyPingResult(running)
        }
    }

    func reactivateHelper() {
        guard !isRegistering, !isResettingHelper else { return }
        invalidateReconciliation()
        let generation = reconciliationGeneration
        Task {
            guard generation == reconciliationGeneration, !isResettingHelper else { return }
            await registerHelper(userInitiated: true, forceReinstall: true)
        }
    }

    func resetOwnBackgroundActivity() {
        guard !isResettingHelper, !isRegistering else { return }
        // Reserve the reset synchronously so rapid clicks cannot queue resets.
        isResettingHelper = true
        invalidateReconciliation()
        Task { await performOwnBackgroundActivityReset() }
    }

    func beginInstallation() {
        guard !isRegistering, !isResettingHelper else { return }
        invalidateReconciliation()
        let generation = reconciliationGeneration
        Task { @MainActor [weak self] in
            guard let self, generation == self.reconciliationGeneration,
                  !self.isResettingHelper else { return }
            let currentStatus = await self.refreshStatus()
            guard generation == self.reconciliationGeneration, !self.isResettingHelper else { return }
            helperLogger.info("[HelperManager] beginInstallation status=\(String(describing: currentStatus))")
            _ = await self.registerHelper(userInitiated: true, forceReinstall: false)
        }
    }

    func installIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self, !self.isReconcilingHelper, !self.isRegistering,
                  !self.isResettingHelper else { return }
            self.isReconcilingHelper = true
            self.reconciliationGeneration += 1
            let generation = self.reconciliationGeneration
            defer {
                if generation == self.reconciliationGeneration {
                    self.isReconcilingHelper = false
                }
            }
            let currentStatus = await self.refreshStatus()
            guard generation == self.reconciliationGeneration else { return }
            helperLogger.info("[HelperManager] installIfNeeded daemon=\(String(describing: currentStatus)) issue=\(self.lastIssue?.code ?? "none")")

            switch currentStatus {
            case .notFound:
                _ = await self.registerHelper(userInitiated: false, forceReinstall: true)
            case .notRegistered:
                _ = await self.registerHelper(userInitiated: false, forceReinstall: false)
            case .enabled:
                await self.reconcileEnabledHelper(generation: generation)
            case .requiresApproval:
                _ = await self.registerHelper(userInitiated: false, forceReinstall: false)
            @unknown default:
                break
            }
        }
    }

    private func invalidateReconciliation() {
        reconciliationGeneration += 1
        isReconcilingHelper = false
    }

    private func reconcileEnabledHelper(generation: Int) async {
        XPCClient.shared.start(force: false)
        for attempt in 1...4 {
            let running = await XPCClient.shared.ping(timeout: 2)
            guard generation == reconciliationGeneration else { return }
            if running {
                applyPingResult(true)
                BatteryManager.shared.helperDidBecomeReachable()
                let compatibility = await helperProtocolCompatibility()
                guard generation == reconciliationGeneration else { return }
                helperLogger.info("[HelperManager] Helper ping ok on attempt \(attempt), compatibility=\(String(describing: compatibility), privacy: .public)")
                if compatibility == .outdated {
                    _ = await registerHelper(userInitiated: false, forceReinstall: true)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard generation == reconciliationGeneration else { return }
        }
        helperLogger.info("[HelperManager] Helper did not respond during startup reconciliation")
        // An enabled service with no reply may still be validating the client.
        // Keep its connection and show the status banner; a timeout alone is
        // not evidence that its launchd registration needs to be rebuilt.
        applyPingResult(false)
    }

    private enum HelperCompatibility {
        case current, outdated, unknown
    }

    private func helperProtocolCompatibility() async -> HelperCompatibility {
        guard let running = await XPCClient.shared.helperProtocolVersion(timeout: 2) else {
            helperLogger.info("[HelperManager] Helper protocol version query unavailable; compatibility is unknown")
            return .unknown
        }
        helperLogger.info("[HelperManager] Helper protocol version: running=\(running) expected=\(SapphireHelperProtocolVersion)")
        return running == SapphireHelperProtocolVersion ? .current : .outdated
    }

    func uninstall() {
        invalidateReconciliation()
        Task { @MainActor [weak self] in
            guard let self else { return }
            XPCClient.shared.stop()
            if let errorDescription = await Self.unregisterDaemon() {
                helperLogger.error("[HelperManager] Helper unregistration failed: \(errorDescription)")
            } else {
                helperLogger.info("[HelperManager] Helper unregistration successful")
            }
            _ = await self.refreshStatus()
        }
    }

    private func performOwnBackgroundActivityReset() async {
        isResettingHelper = true
        isRegistering = true
        defer {
            isRegistering = false
            isResettingHelper = false
        }

        helperLogger.info("[HelperManager] Resetting helper via SMAppService unregister/register")
        XPCClient.shared.stop()

        if let errorDescription = await Self.unregisterDaemon() {
            helperLogger.error("[HelperManager] Helper unregister failed: \(errorDescription)")
        } else {
            helperLogger.info("[HelperManager] Unregistered privileged helper")
        }

        try? await Task.sleep(for: .milliseconds(800))
        _ = await submitRegistration()
        _ = await refreshStatus()
        refreshIssue()

        if await pingUntilRunning() {
            helperLogger.info("[HelperManager] Helper recovered after SMAppService reset")
            return
        }

        helperLogger.info("[HelperManager] Helper still not running; relaunching Sapphire to rebuild BTM")
        HelperManager.relaunchApp()
    }

    @discardableResult
    private func registerHelper(userInitiated: Bool, forceReinstall: Bool) async -> Bool {
        if isRegistering { return false }
        if let last = lastRegisterAttempt, Date().timeIntervalSince(last) < registerCooldown, !userInitiated, !forceReinstall {
            return false
        }

        isRegistering = true
        lastRegisterAttempt = Date()
        defer { isRegistering = false }

        guard bundledPlistIsReadable() else {
            presentIssue(.notFound, force: userInitiated)
            return false
        }

        helperLogger.info("[HelperManager] register() status=\(String(describing: self.status)), bundle=\(Bundle.main.bundlePath, privacy: .public), forceReinstall=\(forceReinstall)")

        if forceReinstall {
            _ = await reinstallHelper()
        } else {
            _ = await submitRegistration()
        }

        _ = await refreshStatus()
        refreshIssue()

        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            presentIssue(.needsApproval, force: true)
            return false
        }

        if status == .notFound {
            if await pingUntilRunning() {
                return true
            }
            presentIssue(.notFound, force: userInitiated)
            return false
        }

        if await pingUntilRunning() {
            let compatibility = await helperProtocolCompatibility()
            // Only an explicit version mismatch warrants reinstalling. A
            // timed-out query must not interrupt a healthy, verified helper.
            if compatibility != .outdated {
                return true
            }
            helperLogger.info("[HelperManager] Running helper is an old build; reinstalling")
            _ = await reinstallHelper()
            if await pingUntilRunning(), await helperProtocolCompatibility() != .outdated {
                return true
            }
        }

        refreshIssue()
        if let issue = lastIssue {
            if userInitiated || issue != .spawnFailed {
                presentIssue(issue, force: userInitiated || issue == .notFound)
            }
        }
        return isRunning
    }

    private func submitRegistration() async -> Bool {
        if let errorDescription = await Self.registerDaemon() {
            helperLogger.error("[HelperManager] register() failed: \(errorDescription)")
            _ = await refreshStatus()
            return false
        }
        helperLogger.info("[HelperManager] register() returned success")
        return true
    }

    @discardableResult
    private func reinstallHelper() async -> Bool {
        helperLogger.info("[HelperManager] unregister() then register() to rebuild the SMAppService job")
        if let errorDescription = await Self.unregisterDaemon() {
            helperLogger.error("[HelperManager] unregister() failed: \(errorDescription)")
        } else {
            helperLogger.info("[HelperManager] unregister() succeeded")
        }

        XPCClient.shared.stop()
        try? await Task.sleep(for: .milliseconds(800))
        return await submitRegistration()
    }

    private func pingUntilRunning() async -> Bool {
        XPCClient.shared.start()
        try? await Task.sleep(for: .milliseconds(600))

        for attempt in 1...5 {
            let running = await XPCClient.shared.ping(timeout: 2)
            helperLogger.info("[HelperManager] Post-register ping \(attempt)/5: \(running ? "running" : "not running")")
            if running {
                applyPingResult(true)
                BatteryManager.shared.helperDidBecomeReachable()
                return true
            }
            try? await Task.sleep(for: .milliseconds(700))
        }
        applyPingResult(false)
        return false
    }

    private func applyPingResult(_ running: Bool) {
        if running {
            consecutiveMissedPings = 0
            isRunning = true
        } else if isRunning {
            consecutiveMissedPings += 1
            if consecutiveMissedPings >= 3 {
                isRunning = false
            }
        } else {
            consecutiveMissedPings += 1
            isRunning = false
        }
        refreshIssue()
    }

    private func refreshIssue() {
        if isRunning {
            lastIssue = nil
            return
        }
        switch status {
        case .notFound:
            lastIssue = .notFound
        case .requiresApproval:
            lastIssue = .needsApproval
        case .enabled:
            lastIssue = .spawnFailed
        case .notRegistered:
            lastIssue = nil
        @unknown default:
            lastIssue = .notFound
        }
    }

    private func presentIssue(_ issue: HelperIssue, force: Bool) {
        if !force, presentedIssuesThisSession.contains(issue.code) { return }
        presentedIssuesThisSession.insert(issue.code)
        HelperAlertPresenter.present(issue)
    }
}

extension SMAppService.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notRegistered: return "Not Registered"
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires Approval"
        case .notFound: return "Not Found"
        @unknown default: return "Unknown"
        }
    }
}
