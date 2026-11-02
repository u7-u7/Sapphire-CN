//
//  PermissionsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import Combine
import CoreLocation
import EventKit
import AVFoundation
import UserNotifications
import ScreenCaptureKit
import CoreBluetooth
import Intents
import ApplicationServices
import AppKit
import CoreServices
import Network

// MARK: - Permission Enums
enum PermissionType: Identifiable, CaseIterable {
    case accessibility, notifications, location, calendar, reminders, bluetooth, focusStatus, fullDiskAccess, screenRecording, localNetwork, automation
    var id: Self { self }
}

enum PermissionStatus: String, CaseIterable {
    case granted, denied, notRequested
}

enum PermissionCategory: String, CaseIterable {
    case required = "Required"
    case recommended = "Recommended"
    case optional = "Optional"
}

struct PermissionItem: Identifiable {
    let id = UUID()
    let type: PermissionType, title: String, description: String, iconName: String
    let iconColor: Color
    let category: PermissionCategory
}

// MARK: - PermissionsManager
@MainActor
class PermissionsManager: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate, @MainActor CBCentralManagerDelegate {
    static let shared = PermissionsManager()

    @Published var accessibilityStatus: PermissionStatus = .notRequested
    @Published var notificationsStatus: PermissionStatus = .notRequested
    @Published var locationStatus: PermissionStatus = .notRequested
    @Published var calendarStatus: PermissionStatus = .notRequested
    @Published var remindersStatus: PermissionStatus = .notRequested
    @Published var bluetoothStatus: PermissionStatus = .notRequested
    @Published var focusStatusStatus: PermissionStatus = .notRequested
    @Published var fullDiskAccessStatus: PermissionStatus = .notRequested
    @Published var screenRecordingStatus: PermissionStatus = .notRequested
    @Published var localNetworkStatus: PermissionStatus = .notRequested
    @Published var automationStatus: PermissionStatus = .notRequested

    private var locationManager: CLLocationManager?
    private lazy var bluetoothManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: 0])

    private let automationPermissionRequestedKey = "automationPermissionRequested"

    private struct AutomationTarget {
        let name: String
        let bundleIdentifier: String
    }

    private let automationTargets = [
        AutomationTarget(name: "Music", bundleIdentifier: "com.apple.Music"),
        AutomationTarget(name: "Spotify", bundleIdentifier: "com.spotify.client"),
    ]

    private var localNetworkListener: NWListener?
    private var dummyNetService: NetService?
    private let localNetworkStatusKey = "localNetworkPermissionStatus"

    private var cancellables = Set<AnyCancellable>()

    public let allPermissions: [PermissionItem] = [
        .init(type: .accessibility, title: "Accessibility", description: "Needed for media key presses, window snapping, and HUDs.", iconName: "figure.wave.circle.fill", iconColor: .purple, category: .required),
        .init(type: .fullDiskAccess, title: "Full Disk Access", description: "Enables File Shelf, Intelligence file access, and deeper system integrations.", iconName: "folder.badge.gearshape", iconColor: .gray, category: .recommended),
        .init(type: .screenRecording, title: "Screen Recording", description: "Required for Gemini Live screen sharing, per-app audio capture, live window previews, and the hinge-driven desktop animation.", iconName: "record.circle", iconColor: .orange, category: .recommended),
        .init(type: .localNetwork, title: "Local Network", description: "Needed to discover and control supported media players on your network.", iconName: "network", iconColor: .cyan, category: .recommended),
        .init(type: .automation, title: "Automation", description: "Needed to control playback and get track info from Spotify and Music.", iconName: "play.display", iconColor: .green, category: .recommended),
        .init(type: .notifications, title: "Notifications", description: "Needed to show custom alerts for messages and system events.", iconName: "bell.badge.fill", iconColor: .red, category: .recommended),
        .init(type: .location, title: "Location", description: "Needed to provide live weather updates for your current location.", iconName: "location.fill", iconColor: .blue, category: .recommended),
        .init(type: .calendar, title: "Calendar", description: "Needed to show your upcoming events.", iconName: "calendar", iconColor: .red, category: .recommended),
        .init(type: .bluetooth, title: "Bluetooth", description: "Needed to detect connected devices and their battery levels.", iconName: "ipad.landscape.and.iphone", iconColor: .blue, category: .recommended),
        .init(type: .reminders, title: "Reminders", description: "Needed to show your upcoming reminders.", iconName: "checklist", iconColor: .orange, category: .optional),
        .init(type: .focusStatus, title: "Focus Status", description: "Needed to show when a Focus mode is active.", iconName: "moon.fill", iconColor: .indigo, category: .optional)
    ]

    var requiredPermissions: [PermissionItem] { allPermissions.filter { $0.category == .required } }
    var recommendedPermissions: [PermissionItem] { allPermissions.filter { $0.category == .recommended } }
    var optionalPermissions: [PermissionItem] { allPermissions.filter { $0.category == .optional } }

    var areAllRequiredPermissionsGranted: Bool {
        requiredPermissions.allSatisfy { status(for: $0.type) == PermissionStatus.granted }
    }

    func arePermissionsGranted(for types: [PermissionType]) -> Bool {
        types.allSatisfy { status(for: $0) == PermissionStatus.granted }
    }

    func missingPermissions(in types: [PermissionType]) -> [PermissionItem] {
        allPermissions.filter { types.contains($0.type) && status(for: $0.type) != PermissionStatus.granted }
    }

    func permissionItems(for types: [PermissionType]) -> [PermissionItem] {
        types.compactMap { type in allPermissions.first(where: { $0.type == type }) }
    }

    var areIntelligencePermissionsGranted: Bool {
        arePermissionsGranted(for: SettingsSection.intelligence.requiredPermissions)
    }

    private override init() {
        super.init()
        self.locationManager = CLLocationManager()
        self.locationManager?.delegate = self
        checkAllPermissions()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkAccessibilityStatus()
                self?.checkFullDiskAccessStatus()
                self?.checkScreenRecordingStatus()
                self?.checkAutomationStatus()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AccessibilityTrustMonitor.trustDidChange)
            .sink { [weak self] _ in
                self?.checkAccessibilityStatus()
            }
            .store(in: &cancellables)
    }

    private func checkAccessibilityStatus() {
        let isTrusted = AccessibilityTrustMonitor.shared.isTrusted
        accessibilityStatus = isTrusted ? PermissionStatus.granted : PermissionStatus.notRequested
    }

    private func checkFullDiskAccessStatus() {
        if let preflight = Self.tccPreflight {
            let result = preflight(Self.serviceSystemPolicyAllFiles, nil)
            switch result {
            case 0: fullDiskAccessStatus = PermissionStatus.granted
            case 1: fullDiskAccessStatus = PermissionStatus.denied
            default: fullDiskAccessStatus = PermissionStatus.notRequested
            }
        } else {
            let testUrl = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
            let canAccess = FileManager.default.isReadableFile(atPath: testUrl.path)
            fullDiskAccessStatus = canAccess ? PermissionStatus.granted : PermissionStatus.notRequested
        }
    }

    private func checkScreenRecordingStatus() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted {
            screenRecordingStatus = PermissionStatus.granted
        } else if UserDefaults.standard.bool(forKey: "screenRecordingRequested") {
            screenRecordingStatus = PermissionStatus.denied
        } else {
            screenRecordingStatus = PermissionStatus.notRequested
        }
    }

    func checkAllPermissions() {
        checkAccessibilityStatus()
        checkFullDiskAccessStatus()
        checkScreenRecordingStatus()
        checkLocalNetworkStatus()
        checkAutomationStatus()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional: self.notificationsStatus = PermissionStatus.granted
                case .denied: self.notificationsStatus = PermissionStatus.denied
                case .notDetermined: self.notificationsStatus = PermissionStatus.notRequested
                @unknown default: self.notificationsStatus = PermissionStatus.notRequested
                }
            }
        }

        updateLocationStatus(for: locationManager?.authorizationStatus ?? .notDetermined)

        let calStatus = EKEventStore.authorizationStatus(for: .event)
        switch calStatus {
        case .fullAccess, .writeOnly: calendarStatus = PermissionStatus.granted
        case .denied, .restricted: calendarStatus = PermissionStatus.denied
        case .notDetermined: calendarStatus = PermissionStatus.notRequested
        @unknown default: calendarStatus = PermissionStatus.notRequested
        }

        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        switch remStatus {
        case .fullAccess, .writeOnly: remindersStatus = PermissionStatus.granted
        case .denied, .restricted: remindersStatus = PermissionStatus.denied
        case .notDetermined: remindersStatus = PermissionStatus.notRequested
        @unknown default: remindersStatus = PermissionStatus.notRequested
        }

        updateBluetoothStatus(for: CBManager.authorization)

        let focusAuthStatus = INFocusStatusCenter.default.authorizationStatus
        switch focusAuthStatus {
        case .authorized: focusStatusStatus = PermissionStatus.granted
        case .denied, .restricted: focusStatusStatus = PermissionStatus.denied
        case .notDetermined: focusStatusStatus = PermissionStatus.notRequested
        @unknown default: focusStatusStatus = PermissionStatus.notRequested
        }
    }

    func status(for type: PermissionType) -> PermissionStatus {
        switch type {
        case .accessibility: return accessibilityStatus
        case .notifications: return notificationsStatus
        case .location: return locationStatus
        case .calendar: return calendarStatus
        case .reminders: return remindersStatus
        case .bluetooth: return bluetoothStatus
        case .focusStatus: return focusStatusStatus
        case .fullDiskAccess: return fullDiskAccessStatus
        case .screenRecording: return screenRecordingStatus
        case .localNetwork: return localNetworkStatus
        case .automation: return automationStatus
        }
    }

    func requestPermission(_ type: PermissionType) {
        switch type {
        case .accessibility:
            AccessibilityPermission.request()

        case .fullDiskAccess:
            requestFullDiskAccessPrePopulation()
            openFullDiskAccessSettings()

        case .screenRecording:
            let granted = CGRequestScreenCaptureAccess()
            UserDefaults.standard.set(true, forKey: "screenRecordingRequested")
            screenRecordingStatus = granted ? .granted : .denied

        case .automation:
            triggerAutomationPermissionRequest()

        case .localNetwork:
            triggerLocalNetworkPrivacyAlert()

        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async { self.checkAllPermissions() }
            }

        case .location:
            locationManager?.requestWhenInUseAuthorization()

        case .calendar:
            Task {
                do { _ = try await EKEventStore().requestFullAccessToEvents() } catch {}
                await MainActor.run { self.checkAllPermissions() }
            }

        case .reminders:
            Task {
                do { _ = try await EKEventStore().requestFullAccessToReminders() } catch {}
                await MainActor.run { self.checkAllPermissions() }
            }

        case .bluetooth:
            if CBManager.authorization == .denied {
                SystemPreferencesPane.bluetooth.open()
            } else {
                bluetoothManager.scanForPeripherals(withServices: nil, options: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.bluetoothManager.stopScan()
                }
            }

        case .focusStatus:
            INFocusStatusCenter.default.requestAuthorization { _ in
                DispatchQueue.main.async { self.checkAllPermissions() }
            }
        }
    }

    func openPermissionSettings(_ type: PermissionType) {
        switch type {
        case .accessibility:
            SystemPreferencesPane.accessibility.open()
        case .fullDiskAccess:
            SystemPreferencesPane.allFiles.open()
        case .screenRecording:
            SystemPreferencesPane.screenCapture.open()
        case .bluetooth:
            SystemPreferencesPane.bluetooth.open()
        case .notifications:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        default:
            SystemPreferencesPane.privacyRoot.open()
        }
    }

    // MARK: - Automation Logic

    private func checkAutomationStatus() {
        guard UserDefaults.standard.bool(forKey: automationPermissionRequestedKey) else {
            automationStatus = PermissionStatus.notRequested
            return
        }

        let installedTargets = automationTargets.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }

        Task {
            var statuses: [PermissionStatus] = []
            for target in installedTargets {
                statuses.append(await getAutomationPermissionStatus(for: target.name))
            }

            if statuses.contains(PermissionStatus.denied) {
                automationStatus = PermissionStatus.denied
            } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == PermissionStatus.granted }) {
                automationStatus = PermissionStatus.granted
            } else {
                automationStatus = PermissionStatus.notRequested
            }
        }
    }

    private func triggerAutomationPermissionRequest() {
        Task(priority: .userInitiated) {
            var foundTarget = false

            for target in automationTargets {
                guard await launchAutomationTarget(target) else { continue }
                foundTarget = true

                print("[PermissionsManager] Requesting Automation permission for \(target.name)...")
                let status = await Self.determineAutomationPermission(
                    for: target.bundleIdentifier,
                    askUserIfNeeded: true
                )
                print("[PermissionsManager] Automation request for \(target.name) returned \(status).")
            }

            guard foundTarget else { return }
            UserDefaults.standard.set(true, forKey: automationPermissionRequestedKey)

            self.checkAutomationStatus()
        }
    }

    private func launchAutomationTarget(_ target: AutomationTarget) async -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty {
            return true
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            print("[PermissionsManager] Application '\(target.name)' not found.")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
                if let error {
                    print("[PermissionsManager] Could not launch \(target.name) for Automation permission: \(error.localizedDescription)")
                }
                continuation.resume(returning: application != nil)
            }
        }
    }

    private nonisolated static func determineAutomationPermission(
        for bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) async -> OSStatus {
        await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            guard let descriptor = target.aeDesc else { return OSStatus(paramErr) }

            return AEDeterminePermissionToAutomateTarget(
                descriptor,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                askUserIfNeeded
            )
        }.value
    }

    private func getAutomationPermissionStatus(for appName: String) async -> PermissionStatus {
        let command = #"tell application "\#(appName)" to get its name"#

        let errorInfo = await executeAppleScript(command: command, for: appName)

        if errorInfo == nil {
            return PermissionStatus.granted
        } else if let errorNumber = errorInfo?[NSAppleScript.errorNumber] as? NSNumber,
                  errorNumber.intValue == -1743 {
            return PermissionStatus.denied
        } else {
            return PermissionStatus.notRequested
        }
    }

    private func executeAppleScript(command: String, for appName: String) async -> NSDictionary? {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName.lowercased() == "spotify" ? "com.spotify.client" : "com.apple.Music") != nil else {
            print("[PermissionsManager] Application '\(appName)' not found.")
            return ["error": "\(appName) not found"]
        }

        var errorInfo: NSDictionary?
        AppleScriptRunner.execute(command, error: &errorInfo)
        return errorInfo
    }

    // MARK: - Full Disk Access

    private func requestFullDiskAccessPrePopulation() {
        guard let request = Self.tccRequest else { return }
        request(Self.serviceSystemPolicyAllFiles, nil) { _ in }
    }

    private func openFullDiskAccessSettings() {
        SystemPreferencesPane.allFiles.open()
    }

    // MARK: - TCC Private SPI (dynamic loading)

    private typealias TCCPreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias TCCRequestFunc = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let tccHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()

    private static let tccPreflight: TCCPreflightFunc? = {
        guard let handle = tccHandle,
              let sym = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(sym, to: TCCPreflightFunc.self)
    }()

    private static let tccRequest: TCCRequestFunc? = {
        guard let handle = tccHandle,
              let sym = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(sym, to: TCCRequestFunc.self)
    }()

    private static let serviceSystemPolicyAllFiles = "kTCCServiceSystemPolicyAllFiles" as CFString

    // MARK: - Local Network Logic

    private func checkLocalNetworkStatus() {
        if let storedStatusRawValue = UserDefaults.standard.string(forKey: localNetworkStatusKey),
           let storedStatus = PermissionStatus(rawValue: storedStatusRawValue) {
            localNetworkStatus = storedStatus
        } else {
            localNetworkStatus = PermissionStatus.notRequested
        }
    }

    private func triggerLocalNetworkPrivacyAlert() {
        guard localNetworkListener == nil else { return }

        do {
            let listener = try NWListener(using: .tcp)
            self.localNetworkListener = listener

            listener.stateUpdateHandler = { [weak self] newState in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch newState {
                    case .ready:
                        if let port = listener.port {
                            print("[PermissionsManager] Local network listener ready on port \(port). Advertising dummy service.")
                            let service = NetService(domain: "local.", type: "_dummy-service._tcp.", name: "PermissionCheck", port: Int32(port.rawValue))
                            self.dummyNetService = service
                            service.publish()
                            self.updateLocalNetworkStatus(PermissionStatus.granted)
                        }
                        self.scheduleStopLocalNetworkCheck()

                    case .failed(let error):
                        print("[PermissionsManager] Local network listener failed: \(error)")
                        self.updateLocalNetworkStatus(PermissionStatus.denied)
                        self.stopLocalNetworkCheck()

                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { newConnection in
                newConnection.cancel()
            }

            listener.start(queue: DispatchQueue(label: "LocalNetworkPermissionTrigger"))

        } catch {
            print("[PermissionsManager] Failed to create NWListener for permission check: \(error)")
            self.updateLocalNetworkStatus(PermissionStatus.denied)
        }
    }

    private func scheduleStopLocalNetworkCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopLocalNetworkCheck()
        }
    }

    private func stopLocalNetworkCheck() {
        if localNetworkListener != nil {
            print("[PermissionsManager] Stopping local network permission check.")
            dummyNetService?.stop()
            dummyNetService = nil
            localNetworkListener?.cancel()
            localNetworkListener = nil
        }
    }

    private func updateLocalNetworkStatus(_ newStatus: PermissionStatus) {
        localNetworkStatus = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: localNetworkStatusKey)
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let wasGranted = locationStatus == PermissionStatus.granted
        updateLocationStatus(for: manager.authorizationStatus)
        if locationStatus == PermissionStatus.granted && !wasGranted {
            WeatherViewModel.shared.fetch()
        }
    }

private func updateLocationStatus(for status: CLAuthorizationStatus) {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: locationStatus = PermissionStatus.granted
        case .denied, .restricted: locationStatus = PermissionStatus.denied
        case .notDetermined: locationStatus = PermissionStatus.notRequested
        @unknown default: locationStatus = PermissionStatus.notRequested
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.updateBluetoothStatus(for: CBManager.authorization)
    }

    private func updateBluetoothStatus(for authorization: CBManagerAuthorization) {
        switch authorization {
        case .allowedAlways: bluetoothStatus = PermissionStatus.granted
        case .denied, .restricted: bluetoothStatus = PermissionStatus.denied
        case .notDetermined: bluetoothStatus = PermissionStatus.notRequested
        @unknown default: bluetoothStatus = PermissionStatus.notRequested
        }
    }
}
