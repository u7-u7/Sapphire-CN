//
//  SettingsPanes.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import Combine
import Charts
import CoreBluetooth
import UniformTypeIdentifiers

struct SettingsDetailView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    var selectedSection: SettingsSection?

    private var isSelectedSectionLocked: Bool {
        selectedSection?.isPremiumLocked ?? false
    }

    var body: some View {
        VStack {
            if let selectedSection, isSelectedSectionLocked {
                LockedSettingsSectionView(section: selectedSection)
            } else {
                settingsPane(for: selectedSection)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedSection)
        .animation(.easeOut(duration: 0.15), value: subscriptionManager.activeTier)
    }

    @ViewBuilder
    private func settingsPane(for selectedSection: SettingsSection?) -> some View {
        switch selectedSection {
        case .general: GeneralSettingsView()
        case .systemEnhance: SystemEnhanceSettingsView()
        case .apps: AppsSettingsView()
        case .storage: StorageSettingsView()
        case .widgets: WidgetsSettingsView()
        case .liveActivities: LiveActivitiesSettingsView()
        case .appearance: AppearanceSettingsView()
        case .lockScreen: LockScreenSettingsView()
        case .bluetoothUnlock: ProximityUnlockSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .keyboardShortcuts: KeyboardShortcutsSettingsView()
        case .snapZones: SnapZonesSettingsView()
        case .audio: AudioSettingsView()
        case .battery: BatterySettingsView()
        case .bluetooth: BluetoothSettingsView()
        case .hud: HUDSettingsView()
        case .notifications: NotificationsSettingsView()
        case .neardrop: NeardropSettingsView()
        case .continuity: ContinuitySettingsView()
        case .fileShelf: FileShelfSettingsView()
        case .notes: NotesSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .emoji: EmojiSettingsView()
        case .mouse: MouseSettingsView()
        case .monitoring: MonitoringSettingsView()
        case .archives: ArchivesAndDMGInstallerSettingsView()
        case .mirror: MirrorSettingsView()
        case .caffeine: CaffeineSettingsView()
        case .devActivity: DevActivitySettingsView()
        case .music: MusicSettingsView()
        case .weather: WeatherSettingsView()
        case .calendar: CalendarSettingsView()
        case .eyeBreak: EyeBreakSettingsView()
        case .focusSession: FocusSessionSettingsView()
        case .appLock: AppLockSettingsView()
        case .intelligence: IntelligenceSettingsView()
        case .sports: SportsSettingsView()
        case .finance: FinanceSettingsView()
        case .dockLayouts: DockLayoutsSettingsView()
        case .mediaOptimizer: MediaOptimizerSettingsView()
        case .about: AboutSettingsView()
        case nil:
            VStack {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 50))
                        .foregroundStyle(.tertiary)
                    Text("Select a category")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct LockedSettingsSectionView: View {
    let section: SettingsSection

    private var requiredTierName: String {
        guard let tier = section.minimumRequiredTier else { return "Premium" }
        return SubscriptionFeatureCatalog.tierDisplayName(tier)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(String(format: NSLocalizedString("%@ requires Sapphire %@", comment: "Premium settings requirement"), section.label, requiredTierName))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Upgrade from Account to unlock this section.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Open Account Settings") {
                NotificationCenter.default.post(name: .sapphireOpenAccountPane, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RequiredPermissionsView: View {
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    let section: SettingsSection
    private var requiredPermissions: [PermissionItem] { permissionsManager.allPermissions.filter { section.requiredPermissions.contains($0.type) } }
    private var missingPermissions: [PermissionItem] { requiredPermissions.filter { permissionsManager.status(for: $0.type) != .granted } }
    var body: some View {
        if !requiredPermissions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !missingPermissions.isEmpty {
                    missingPermissionsWarning
                }
                Text("Required Permissions").font(.headline).padding([.horizontal, .top])
                ForEach(requiredPermissions) { permission in
                    PermissionStatusRowView(permission: permission)
                    if permission.id != requiredPermissions.last?.id { Divider().padding(.leading, 60) }
                }
            }.modifier(SettingsContainerModifier()).onAppear(perform: permissionsManager.checkAllPermissions)
        }
    }

    private var missingPermissionsWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(missingPermissionsMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
            )
        }
        .padding([.horizontal, .top])
    }

    private var missingPermissionsMessage: String {
        let names = missingPermissions.map(\.title)
        if names.isEmpty { return "" }
        if names.count == 1 {
            return "\(names[0]) permission has not been granted. Some features may not work until it is enabled."
        }
        let list = names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "\(list) permissions have not been granted. Some features may not work until they are enabled."
    }
}

struct PermissionStatusRowView: View {
    let permission: PermissionItem
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: permission.iconName).font(.system(size: 18, weight: .medium)).foregroundColor(permission.iconColor).frame(width: 36, height: 36).background(permission.iconColor.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(permission.title, comment: "Permission name")).font(.system(size: 14, weight: .medium))
                Text(NSLocalizedString(permission.description, comment: "Permission purpose")).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            let status = permissionsManager.status(for: permission.type)
            switch status {
            case .granted: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
            case .denied: Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
            case .notRequested: Button("Request") { permissionsManager.requestPermission(permission.type) }.buttonStyle(.bordered).tint(.accentColor)
            }
            PermissionFeatureInfoButton(permission: permission)
                .padding(.trailing, 4)
        }.padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}

struct PermissionFeatureInfoButton: View {
    let permission: PermissionItem
    @State private var isShowingInfo = false

    var body: some View {
        Button {
            isShowingInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("See which features require this permission")
        .popover(isPresented: $isShowingInfo, arrowEdge: .trailing) {
            PermissionFeatureInfoPopover(permission: permission)
        }
    }
}

struct PermissionFeatureInfoPopover: View {
    let permission: PermissionItem

    private var features: [SettingsSection] { SettingsSection.features(requiring: permission.type) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(NSLocalizedString(permission.title, comment: "Permission name"))
            } icon: {
                Image(systemName: permission.iconName)
                    .foregroundStyle(permission.iconColor)
            }
            .font(.headline)

            Divider()

            if features.isEmpty {
                Text(NSLocalizedString(permission.description, comment: "Permission purpose"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Required for")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(features, id: \.self) { section in
                    HStack(spacing: 8) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 12))
                            .foregroundStyle(section.iconBackgroundColor)
                            .frame(width: 16)
                        Text(section.label)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

struct NotchAppearanceEditorView: View {
    @Binding var appearance: NotchAppearanceSettings
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(NSLocalizedString(title, comment: "Settings title")).font(.headline).padding([.top, .horizontal])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Style")
                Spacer()
                Picker("", selection: $appearance.mode) {
                    ForEach(NotchAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 310)
            }
            .padding()

            if appearance.mode == .liquidGlass || appearance.mode == .custom {
                Divider().padding(.leading, 20)
                LiquidGlassStylePickerRow(selection: $appearance.liquidGlassStyle)
            }

            if appearance.mode == .default {
                Divider().padding(.leading, 20)
                ToggleRow(
                    title: "Fade Bottom Edge",
                    description: "Fade the lower edge of the notch from black to transparent.",
                    isOn: $appearance.bottomFadeEnabled
                )
            }

            if appearance.mode == .custom {
                Divider().padding(.leading, 20)
                ToggleRow(
                    title: "Liquid Glass",
                    description: "Use the liquid glass material for the custom notch background.",
                    isOn: $appearance.liquidGlassLook
                )

                Divider().padding(.leading, 20)
                HStack {
                    Text("Background Style")
                    Spacer()
                    Picker("", selection: $appearance.backgroundStyle) {
                        ForEach(NotchBackgroundStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }.labelsHidden().frame(width: 150)
                }.padding()

                if appearance.backgroundStyle == .solid {
                    solidColorPicker
                } else {
                    gradientColorEditor
                }

                Divider().padding(.leading, 20)
                let opacityBinding = Binding<Double>(
                    get: { appearance.opacity * 100 },
                    set: { appearance.opacity = min(max($0 / 100, 0), 1) }
                )
                CustomSliderRowView(label: "Master Opacity", value: opacityBinding, range: 0...100, specifier: "%.0f%%")
            }

            if appearance.mode == .blur || (appearance.mode == .custom && !appearance.liquidGlassLook) {
                Divider().padding(.leading, 20)
                ToggleRow(title: "Enable Transparency Blur", description: "Apply a frosted glass effect to the notch background.", isOn: $appearance.enableTransparencyBlur)
            }
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: appearance.backgroundStyle)
        .animation(.default, value: appearance.mode)
        .animation(.default, value: appearance.enableTransparencyBlur)
    }

    @ViewBuilder
    private var solidColorPicker: some View {
        ColorPicker("Color", selection: $appearance.solidColor.color, supportsOpacity: true)
        .padding()
        .transition(.opacity)
    }

    @ViewBuilder
    private var gradientColorEditor: some View {
        VStack(alignment: .leading) {
            if appearance.backgroundStyle == .gradient {
                CustomSliderRowView(label: "Angle", value: $appearance.gradientAngle, range: 0...360, specifier: "%.0f°")
                    .padding(.horizontal)
            }

            Text("Gradient Colors").font(.subheadline).padding(.horizontal)

            ForEach($appearance.gradientColors) { $color in
                VStack(spacing: 8) {
                    HStack {
                        ColorPicker("Color Stop", selection: $color.color, supportsOpacity: true)
                        Spacer()
                        Button(action: {
                            guard appearance.gradientColors.count > 1 else { return }
                            let doomed = color.id
                            DispatchQueue.main.async {
                                appearance.gradientColors.removeAll { $0.id == doomed }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(appearance.gradientColors.count <= 1)
                    }
                    DeferredValueEditor(value: $color.location.asDouble) { draft, onEditingChanged in
                        Slider(
                            value: draft,
                            in: 0...1,
                            label: { Text("Location") },
                            minimumValueLabel: { Text("0%") },
                            maximumValueLabel: { Text("100%") },
                            onEditingChanged: onEditingChanged
                        )
                    }
                }.padding(.horizontal)
            }

            Button(action: {
                var updatedColors = appearance.gradientColors
                if let lastColor = updatedColors.last {
                    let newLocation = min(1.0, lastColor.location + 0.2)
                    let newColorStop = CodableColor(color: lastColor.color, location: newLocation)
                    updatedColors.append(newColorStop)
                } else {
                    let newColorStop = CodableColor(color: .black, location: 0.0)
                    updatedColors.append(newColorStop)
                }
                appearance.gradientColors = updatedColors.sorted { $0.location < $1.location }
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Color Stop")
                }
            }
            .buttonStyle(.plain)
            .tint(.accentColor)
            .padding(.top, 5)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .transition(.opacity)
    }
}

struct SystemEnhanceSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("System").font(.largeTitle.bold())
                Text("Desktop motion, input, and window enhancements that stay out of your way.")
                    .font(.subheadline).foregroundStyle(.secondary)

                SystemEnhanceHingeAnimationSettingsCard()

                VStack(alignment: .leading, spacing: 0) {
                    PremiumFeatureView(feature: .windowsPreview) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("App Switching").font(.headline).padding([.top, .horizontal])
                            ToggleRow(title: "Window Switcher", description: "Replace the switcher with a keyboard-driven, window-aware overlay. Hold the shortcut and press Tab to cycle, arrows to move, Q to quit an app, W to close a window.", isOn: $settings.settings.systemEnhanceAltTabEnabled)
                            if settings.settings.systemEnhanceAltTabEnabled {
                                Divider().padding(.leading, 20)
                                HStack { Text("Activate With"); Spacer(); Picker("", selection: Binding(
                                    get: { settings.settings.systemEnhanceSwitcherActivation.rawValue },
                                    set: { settings.settings.systemEnhanceSwitcherActivation = SESwitcherActivation(rawValue: $0) ?? .both }
                                )) {
                                    Text("⌘ Tab").tag(SESwitcherActivation.command.rawValue)
                                    Text("⌥ Tab").tag(SESwitcherActivation.option.rawValue)
                                    Text("Both").tag(SESwitcherActivation.both.rawValue)
                                }.labelsHidden().frame(width: 160) }.padding()
                                Divider().padding(.leading, 20)
                                ToggleRow(title: "Include Windows From Other Spaces", description: "Also list windows on other Spaces and full-screen apps. Selecting one switches to its Space.", isOn: $settings.settings.systemEnhanceSwitcherIncludeOtherSpaces)
                                Divider().padding(.leading, 20)
                                HStack { Text("Window Switcher Layout"); Spacer(); Picker("", selection: Binding(
                                    get: { settings.settings.systemEnhanceWindowSwitcherLayout.rawValue },
                                    set: { settings.settings.systemEnhanceWindowSwitcherLayout = SEPreviewLayout(rawValue: $0) ?? .grid }
                                )) { Text("Grid").tag(SEPreviewLayout.grid.rawValue); Text("List").tag(SEPreviewLayout.list.rawValue); Text("Carousel").tag(SEPreviewLayout.carousel.rawValue) }.labelsHidden().frame(width: 150) }.padding()
                            }
                        }
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Input Behavior").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Paste as Plain Text", description: "Remove text formatting when using Command-V.", isOn: $settings.settings.systemEnhancePasteAsPlainTextEnabled)
                    if settings.settings.systemEnhancePasteAsPlainTextEnabled {
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Remove Links", description: "Strip web addresses from pasted text.", isOn: $settings.settings.systemEnhancePasteAsPlainStripLinks)
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Remove Emojis", description: "Strip emoji characters from pasted text.", isOn: $settings.settings.systemEnhancePasteAsPlainStripEmojis)
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Remove List Markers", description: "Remove bullets and numbered markers such as •, -, and 1. from list items.", isOn: $settings.settings.systemEnhancePasteAsPlainStripListMarkers)
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Calendar Integration").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Calendar Integration", description: "Include calendar context in enhanced window and Dock previews.", isOn: $settings.settings.systemEnhanceCalendarIntegrationEnabled)
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Quit on Close").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Quit Apps When Their Last Window Closes", description: "Apps quit themselves once they have no windows left, after a short grace period. Enabled for every app by default.", isOn: $settings.settings.systemEnhanceAutoQuitEnabled)
                    if settings.settings.systemEnhanceAutoQuitEnabled {
                        Divider().padding(.leading, 20)
                        Text("Apps to quit when window-less:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        AppTogglesListView(
                            isEnabled: { app in $settings.settings.systemEnhanceAutoQuitExcludedApps.membership(of: app.id).negated },
                            showSearch: true
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Quit & Close Protection").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Protect Quit and Close Shortcuts", description: "Require a hold, a double press, or an extra modifier for ⌘Q and ⌘W. Enabled for every app by default.", isOn: $settings.settings.systemEnhanceQuitProtectionEnabled)
                    if settings.settings.systemEnhanceQuitProtectionEnabled {
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Protect ⌘Q (Quit)", description: "Require confirmation before the app quits.", isOn: $settings.settings.systemEnhanceQuitProtectionProtectQuit)
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Protect ⌘W (Close Window)", description: "Require confirmation before a window closes.", isOn: $settings.settings.systemEnhanceQuitProtectionProtectClose)
                        Divider().padding(.leading, 20)
                        HStack { Text("Protection Mode"); Spacer(); Picker("", selection: Binding(
                            get: { settings.settings.systemEnhanceQuitProtectionMode.rawValue },
                            set: { settings.settings.systemEnhanceQuitProtectionMode = SEQuitProtectionMode(rawValue: $0) ?? .hold }
                        )) {
                            Text("Hold the Shortcut").tag(SEQuitProtectionMode.hold.rawValue)
                            Text("Double Press").tag(SEQuitProtectionMode.doublePress.rawValue)
                            Text("Require Extra Modifier").tag(SEQuitProtectionMode.extraModifier.rawValue)
                        }.labelsHidden().frame(width: 200) }.padding()
                        if settings.settings.systemEnhanceQuitProtectionMode == .hold {
                            Divider().padding(.leading, 20)
                            CustomSliderRowView(label: "Hold Duration", value: $settings.settings.systemEnhanceQuitProtectionHoldInterval, range: 0.4...3, specifier: "%.2fs").padding(.horizontal)
                        }
                        if settings.settings.systemEnhanceQuitProtectionMode == .doublePress {
                            Divider().padding(.leading, 20)
                            CustomSliderRowView(label: "Double Press Window", value: $settings.settings.systemEnhanceQuitProtectionDoublePressInterval, range: 0.2...1.5, specifier: "%.2fs").padding(.horizontal)
                        }
                        if settings.settings.systemEnhanceQuitProtectionMode == .extraModifier {
                            Divider().padding(.leading, 20)
                            HStack { Text("Extra Modifier"); Spacer(); Picker("", selection: Binding(
                                get: { settings.settings.systemEnhanceQuitProtectionExtraModifier.rawValue },
                                set: { settings.settings.systemEnhanceQuitProtectionExtraModifier = SEQuitProtectionExtraModifier(rawValue: $0) ?? .option }
                            )) {
                                Text("⌥ Option").tag(SEQuitProtectionExtraModifier.option.rawValue)
                                Text("⌃ Control").tag(SEQuitProtectionExtraModifier.control.rawValue)
                                Text("⇧ Shift").tag(SEQuitProtectionExtraModifier.shift.rawValue)
                            }.labelsHidden().frame(width: 140) }.padding()
                        }
                        Divider().padding(.leading, 20)
                        Text("Apps with protected ⌘Q/⌘W:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        AppTogglesListView(
                            isEnabled: { app in $settings.settings.systemEnhanceQuitProtectionExcludedApps.membership(of: app.id).negated },
                            showSearch: true
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Green Button Maximize").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Maximize in Current Space", description: "The green traffic-light button fills the screen without creating a new Space; clicking it again restores the window.", isOn: $settings.settings.systemEnhanceGreenMaximizeEnabled)
                }.modifier(SettingsContainerModifier())
            }.padding(25)
        }
    }
}

private struct SystemEnhanceHingeAnimationSettingsCard: View {
    @EnvironmentObject private var settings: SettingsEditingSession
    @ObservedObject private var lidAngleSensor = LidAngleSensor.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    private var currentLidAngleText: String {
        guard lidAngleSensor.isAvailable else { return "Unavailable" }
        guard lidAngleSensor.isReporting else { return "Connecting…" }
        return "\(Int(lidAngleSensor.angle.rounded()))°"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        }
    }
}

struct AppsSettingsView: View {
    @EnvironmentObject private var settingsModel: SettingsEditingSession
    @ObservedObject private var installedUpdates = InstalledAppUpdatesChecker.shared
    @StateObject private var appModel = InstalledAppsViewModel()
    @State private var selectedTab: AppsTab = .updates
    @State private var updatesQuery = ""
    @State private var uninstallQuery = ""
    @State private var updateFilter: AppUpdateFilter = .updates
    @State private var showSystemApps = false
    @State private var reviewApp: InstalledApp?

    private enum AppsTab: String, CaseIterable, Identifiable {
        case updates = "Updates"
        case uninstall = "Uninstall"
        var id: String { rawValue }
        var icon: String { self == .updates ? "arrow.triangle.2.circlepath" : "trash" }
    }

    private enum AppUpdateFilter: String, CaseIterable, Identifiable {
        case updates = "Updates"
        case current = "Current"
        case attention = "Needs attention"
        case ignored = "Ignored"
        case all = "All"
        var id: String { rawValue }
    }

    private struct UpdateSnapshot {
        var filteredEntries: [InstalledAppUpdateEntry] = []
        var availableCount = 0
        var currentCount = 0
        var unsupportedCount = 0
        var checkingCount = 0
    }

    private var updateSnapshot: UpdateSnapshot {
        let query = updatesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let ignoredIDs = installedUpdates.ignoredBundleIDs
        var snapshot = UpdateSnapshot()

        for entry in installedUpdates.entries {
            let isIgnored = ignoredIDs.contains(entry.id)
            if entry.status.isUpdateAvailable && !isIgnored { snapshot.availableCount += 1 }
            if entry.status.isUpToDate && !isIgnored { snapshot.currentCount += 1 }
            if entry.status.isUnsupported && !isIgnored { snapshot.unsupportedCount += 1 }
            if entry.status == .checking { snapshot.checkingCount += 1 }

            let matchesQuery = query.isEmpty
                || entry.name.localizedCaseInsensitiveContains(query)
                || entry.bundleIdentifier.localizedCaseInsensitiveContains(query)
            guard matchesQuery else { continue }

            let matchesFilter: Bool
            switch updateFilter {
            case .updates: matchesFilter = entry.status.isUpdateAvailable && !isIgnored
            case .current: matchesFilter = entry.status.isUpToDate && !isIgnored
            case .attention: matchesFilter = (entry.status.isUnsupported || entry.status.isError) && !isIgnored
            case .ignored: matchesFilter = isIgnored
            case .all: matchesFilter = true
            }
            if matchesFilter {
                snapshot.filteredEntries.append(entry)
            }
        }
        return snapshot
    }

    var body: some View {
        let snapshot = updateSnapshot

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header(availableCount: snapshot.availableCount)

                switch selectedTab {
                case .updates:
                    updatesPane(snapshot: snapshot)
                case .uninstall:
                    uninstallPane
                }
            }
            .padding(25)
        }
        .onAppear {
            if settingsModel.settings.installedAppUpdatesEnabled,
               installedUpdates.entries.isEmpty {
                installedUpdates.checkInBackgroundIfNeeded(force: true)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .uninstall { loadInstalledAppInventoryIfNeeded() }
        }
        .onChange(of: settingsModel.settings.installedAppUpdatesEnabled) { _, _ in syncInstalledUpdateSettings() }
        .onChange(of: settingsModel.settings.installedAppUpdateNotificationsEnabled) { _, enabled in
            syncInstalledUpdateSettings()
            if enabled { installedUpdates.requestNotificationAuthorization() }
        }
        .sheet(item: $reviewApp) { app in
            AppUninstallReviewSheet(app: app, model: appModel)
        }
        .sheet(item: $installedUpdates.releaseNotesEntry) { item in
            InstalledAppReleaseNotesSheet(entry: item)
        }
        .onDisappear {
            appModel.cancelScan()
            appModel.cancelArtifactScan()
        }
    }

    private func header(availableCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apps")
                        .font(.largeTitle.bold())
                    Text("Keep installed apps current and review app-linked data before cleanup.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if availableCount > 0 {
                    Label("\(availableCount) available", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.13), in: Capsule())
                }
            }

            Picker("Apps section", selection: $selectedTab) {
                ForEach(AppsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func updatesPane(snapshot: UpdateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    updateMetricCards(snapshot: snapshot)
                        .frame(minWidth: 170)
                }
                VStack(spacing: 10) {
                    updateMetricCards(snapshot: snapshot)
                }
            }

            installedAppsUpdateCard(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func updateMetricCards(snapshot: UpdateSnapshot) -> some View {
        AppsMetricCard(
            title: "Updates",
            value: "\(snapshot.availableCount)",
            detail: snapshot.availableCount == 1 ? "app available" : "apps available",
            systemImage: "arrow.down.circle.fill",
            tint: .blue
        )
        AppsMetricCard(
            title: "Current",
            value: "\(snapshot.currentCount)",
            detail: snapshot.currentCount == 1 ? "app up to date" : "apps up to date",
            systemImage: "checkmark.circle.fill",
            tint: .green
        )
        AppsMetricCard(
            title: "Needs attention",
            value: "\(snapshot.unsupportedCount)",
            detail: snapshot.unsupportedCount == 1 ? "app unsupported" : "apps unsupported",
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange
        )
    }

    private func installedAppsUpdateCard(snapshot: UpdateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Installed app updates", systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Spacer()
                Text("Last checked \(installedUpdates.lastCheckedDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    installedUpdates.checkNow()
                } label: {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(
                    installedUpdates.isChecking
                        || installedUpdates.updatingBundleID != nil
                        || !settingsModel.settings.installedAppUpdatesEnabled
                )
            }

            VStack(spacing: 0) {
                ToggleRow(
                    title: "Monitor installed apps",
                    description: "Use each app's App Store, Homebrew, Sparkle, Electron, Google, or Mozilla channel.",
                    isOn: $settingsModel.settings.installedAppUpdatesEnabled
                )
                Divider().padding(.leading)
                ToggleRow(
                    title: "Installed app notifications",
                    description: "Notify you when a background scan discovers new updates.",
                    isOn: $settingsModel.settings.installedAppUpdateNotificationsEnabled
                )
                .disabled(!settingsModel.settings.installedAppUpdatesEnabled)
                .opacity(settingsModel.settings.installedAppUpdatesEnabled ? 1 : 0.5)
            }
            .modifier(SettingsContainerModifier())

            AppsSearchField(placeholder: "Search update results", text: $updatesQuery)

            Picker("Update filter", selection: $updateFilter) {
                ForEach(AppUpdateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if installedUpdates.isChecking {
                HStack(spacing: 10) {
                    ProgressView(value: installedUpdates.checkProgress)
                        .progressViewStyle(.linear)
                    Text("\(snapshot.checkingCount) remaining")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0) {
                if snapshot.filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No matching apps",
                        systemImage: updateFilter == .updates ? "checkmark.circle" : "magnifyingglass",
                        description: Text(updateFilter == .updates ? "No installed app updates are currently available." : "Try a different filter or search.")
                    )
                    .frame(minHeight: 150)
                } else {
                    let lastEntryID = snapshot.filteredEntries.last?.id
                    ForEach(snapshot.filteredEntries) { entry in
                        InstalledAppUpdateRowView(entry: entry, checker: installedUpdates)
                        if entry.id != lastEntryID { Divider().padding(.leading, 60) }
                    }
                }
            }
            .modifier(SettingsContainerModifier())
        }
    }

    private var uninstallPane: some View {
        let query = uninstallQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = appModel.apps.filter { app in
            (showSystemApps || !app.isSystem)
                && (query.isEmpty
                    || app.name.localizedCaseInsensitiveContains(query)
                    || app.bundleIdentifier.localizedCaseInsensitiveContains(query))
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reviewed app cleanup")
                        .font(.headline)
                    Text("The app is selected automatically. Related files stay unchecked whenever exclusive ownership cannot be proven.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appModel.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appModel.isLoading)
            }
            .padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.2)))

            HStack(spacing: 12) {
                AppsSearchField(placeholder: "Search installed apps", text: $uninstallQuery)
                Toggle("System apps", isOn: $showSystemApps)
                    .toggleStyle(.checkbox)
                    .fixedSize()
            }

            if appModel.isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Scanning Applications…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel scan") { appModel.cancelScan() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 12)
            }

            if let scanError = appModel.scanError, !scanError.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Some applications could not be scanned")
                            .font(.subheadline.weight(.semibold))
                        Text(scanError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .help(scanError)
                    }
                    Spacer()
                    Button("Rescan") { appModel.rescan() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appModel.isLoading)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            LazyVStack(spacing: 0) {
                if !appModel.isLoading && apps.isEmpty {
                    ContentUnavailableView.search(text: uninstallQuery)
                        .frame(minHeight: 180)
                } else {
                    let lastAppID = apps.last?.id
                    ForEach(apps) { app in
                        HStack(spacing: 12) {
                            CachedAppIconView(url: app.url, size: 40, cornerRadius: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).font(.headline)
                                Text(app.isSystem
                                    ? "Version \(app.version) · protected app"
                                    : "Version \(app.version) · \(app.formattedSize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(app.bundleIdentifier)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if installedUpdates.updatingBundleID == app.bundleIdentifier {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Updating…")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else if app.isSystem {
                                Label("Protected", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Review Uninstall…") {
                                    appModel.select(app)
                                    reviewApp = app
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        if app.id != lastAppID { Divider().padding(.leading, 66) }
                    }
                }
            }
            .modifier(SettingsContainerModifier())
        }
    }

    private func syncInstalledUpdateSettings() {
        installedUpdates.applySettings(
            installedAppUpdatesEnabled: settingsModel.settings.installedAppUpdatesEnabled,
            notificationsEnabled: settingsModel.settings.installedAppUpdateNotificationsEnabled
        )
    }

    private func loadInstalledAppInventoryIfNeeded() {
        guard appModel.apps.isEmpty, !appModel.isLoading else { return }
        appModel.scan()
    }

}

private struct AppsMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(title, comment: "Settings title")).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.1)))
    }
}

private struct AppsSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ClearableSearchField(placeholder: LocalizedStringKey(placeholder), text: $text)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AppUninstallReviewSheet: View {
    let app: InstalledApp
    @ObservedObject var model: InstalledAppsViewModel
    @Environment(\.dismiss) private var dismiss

    private var groupedArtifacts: [(AppArtifactCategory, [AppUninstallArtifact])] {
        Dictionary(grouping: model.artifacts, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CachedAppIconView(url: app.url, size: 48, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Uninstall \(app.name)").font(.title2.bold())
                    Text("The app is selected. Identifier-linked, shared, and name-based data requires review unless ownership is verified.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(model.isRemoving)
            }
            .padding(20)

            Divider()

            if model.isScanningArtifacts {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Finding related files…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = model.uninstallResult, result.appName == app.name {
                uninstallResultView(result)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.artifacts.contains(where: { $0.confidence != .exact }) {
                            Label("Unverified, shared, nested-component, duplicate-identifier, and app-name matches stay unchecked until you review them.", systemImage: "exclamationmark.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }

                        ForEach(groupedArtifacts, id: \.0.id) { category, artifacts in
                            VStack(alignment: .leading, spacing: 0) {
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .font(.headline)
                                    .padding(.bottom, 7)
                                ForEach(artifacts) { artifact in
                                    Toggle(isOn: Binding(
                                        get: { model.selectedArtifactIDs.contains(artifact.id) },
                                        set: { model.setArtifact(artifact, selected: $0) }
                                    )) {
                                        HStack(spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(artifact.url.lastPathComponent)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                Text(artifact.url.path)
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                if artifact.confidence != .exact {
                                                    Text(artifact.confidence.explanation)
                                                        .font(.caption2)
                                                        .foregroundStyle(.orange)
                                                }
                                            }
                                            Spacer()
                                            if artifact.requiresAuthorization {
                                                Image(systemName: "lock.fill")
                                                    .foregroundStyle(.secondary)
                                                    .help("Administrator access may be required")
                                            }
                                            Text(artifact.formattedSize)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(artifact.isApplication || model.isRemoving)
                                    .padding(.vertical, 7)
                                    if artifact.id != artifacts.last?.id { Divider().padding(.leading, 24) }
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1)))
                        }
                    }
                    .padding(20)
                }

                Divider()
                HStack {
                    Menu("Selection") {
                        Button("Recommended") { model.selectRecommendedArtifacts() }
                        Button("Select All Related Files") { model.selectAllArtifacts() }
                    }
                    .disabled(model.isRemoving)
                    Text("\(model.selectedArtifacts.count) items · \(model.selectedSize.formatted(.byteCount(style: .file)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        model.requestRemoval(app)
                    } label: {
                        if model.isRemoving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Uninstall \(app.name)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.isRemoving || model.selectedArtifacts.isEmpty)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 700)
        .interactiveDismissDisabled(model.isRemoving)
        .onDisappear {
            if !model.isRemoving { model.cancelArtifactScan() }
        }
        .alert("Move app and selected related files to Trash?", isPresented: $model.confirmingRemoval) {
            Button("Uninstall", role: .destructive) { model.removeConfirmed() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.removalMessage)
        }
    }

    @ViewBuilder
    private func uninstallResultView(_ result: AppUninstallResult) -> some View {
        VStack(spacing: 14) {
            Image(systemName: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(result.succeeded ? .green : .orange)
            Text(result.applicationRemoved
                ? (result.succeeded ? "App and selected data removed" : "App removed with some leftovers")
                : "App could not be removed")
                .font(.title3.bold())
            Text("\(result.removed.count) item\(result.removed.count == 1 ? "" : "s") moved to Trash.")
                .foregroundStyle(.secondary)
            if !result.failures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.url.path).font(.caption.monospaced()).lineLimit(1)
                            Text(failure.message).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(30)
    }
}

private struct InstalledAppUpdateRowView: View {
    let entry: InstalledAppUpdateEntry
    let checker: InstalledAppUpdatesChecker

    var body: some View {
        HStack(spacing: 12) {
            CachedAppIconView(url: entry.url, size: 36, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                switch entry.status {
                case .checking:
                    Text("Checking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .upToDate(let latest):
                    Text("Version \(entry.currentVersion) · Up to date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if AppVersionOrdering.isNewer(latest, than: entry.currentVersion) {
                        Text("Latest available: \(latest)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                case .updateAvailable(let latest, _, _, let releaseNotes, _):
                    HStack(spacing: 6) {
                        Text("\(entry.currentVersion) → \(latest)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        if let releaseNotes, !releaseNotes.isEmpty {
                            Button("Release notes") {
                                checker.releaseNotesEntry = InstalledAppUpdatesChecker.ReleaseNotesEntry(entry: entry)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    if checker.buttonLabel(for: entry) == "Open App" {
                        Text("Uses its own signed updater — Sapphire will open the app.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                case .unsupported:
                    Text(checker.canOpenManagedUpdater(for: entry)
                        ? "Updates are managed inside this app"
                        : "No update source found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                case .ignored:
                    Text("Ignored")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                case .error(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusActions
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusActions: some View {
        switch entry.status {
        case .updateAvailable:
            HStack(spacing: 8) {
                if checker.updatingBundleID == entry.id {
                    ProgressView()
                        .controlSize(.small)
                    Text("Upgrading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(checker.buttonLabel(for: entry)) {
                        checker.updateAction(for: entry.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Menu {
                    Button("Ignore this app") { checker.setIgnored(true, for: entry.id) }
                    if case .updateAvailable(_, _, let pageURL, _, _) = entry.status, let pageURL {
                        Button(checker.isAppStoreEntry(entry) ? "Open in App Store" : "Open update page") {
                            checker.openUpdatePage(for: entry, pageURL: pageURL)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        case .checking, .upToDate:
            Menu {
                Button("Check again") { checker.checkAgain(entryID: entry.id) }
                Button("Ignore this app") { checker.setIgnored(true, for: entry.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        case .ignored, .unsupported, .error:
            Menu {
                if checker.canOpenManagedUpdater(for: entry) {
                    Button("Open app updater") { checker.openManagedUpdater(entryID: entry.id) }
                }
                Button("Check again") { checker.checkAgain(entryID: entry.id) }
                Button(checker.isIgnored(entry) ? "Stop ignoring" : "Ignore this app") {
                    checker.setIgnored(!checker.isIgnored(entry), for: entry.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct InstalledAppReleaseNotesSheet: View {
    let entry: InstalledAppUpdatesChecker.ReleaseNotesEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CachedAppIconView(url: entry.url, size: 40, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.name) \(entry.latestVersion)")
                        .font(.headline)
                    Text("Release notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            ScrollView {
                if let notes = entry.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let url = entry.releaseNotesURL {
                    VStack(spacing: 12) {
                        Text("Notes are published online.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Open in Browser") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    Text("No release notes were published for this update.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
    }
}

struct StorageSettingsView: View {
    @StateObject private var model = StorageViewModel()

    var body: some View {
        ScrollView {
            PremiumFeatureView(feature: .basicStorageFeatures) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Storage")
                            .font(.largeTitle.bold())
                        Text("See exactly what is using space, trace what changed, and reclaim it safely.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if model.currentURL.path != "/" {
                        StorageBreadcrumbBar(model: model)
                    }

                    StorageWorkspaceView(model: model)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(MaterialChartPalette.tertiary)
                        Text("Protected system locations are inspection-only. Every cleanup is reviewed and moved to Trash before space is reclaimed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(25)
            }
        }
        .onAppear { model.refreshFromCache() }
        .onDisappear { model.cancelScan() }
        .alert("Move item to Trash?", isPresented: $model.confirmingRemoval) {
            Button("Move to Trash", role: .destructive) { model.removeConfirmed() }
            Button("Cancel", role: .cancel) { model.cancelRemovalRequest() }
        } message: { Text(model.removalMessage) }
    }
}

private struct StorageBreadcrumbBar: View {
    @ObservedObject var model: StorageViewModel

    private var pathComponents: [(String, URL)] {
        let path = model.currentURL.standardizedFileURL.path
        let parts = path.split(separator: "/").map(String.init)
        var result: [(String, URL)] = [("Macintosh HD", URL(fileURLWithPath: "/"))]
        var url = URL(fileURLWithPath: "/")
        for part in parts where part != "" {
            url.appendPathComponent(part)
            result.append((part, url))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.goUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
            .disabled(model.currentURL.path == "/")
            .help("Go to parent folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            model.open(StorageEntry(url: component.1, size: 0, isDirectory: true))
                        } label: {
                            Label(component.0, systemImage: index == 0 ? "internaldrive.fill" : "folder.fill")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(index == pathComponents.count - 1 ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(index == pathComponents.count - 1 ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.10)))
                    }
                }
                .padding(.vertical, 2)
            }

            Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12)))
                .help("Refresh folder contents")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)))
    }
}

private struct IndexingPill: View {
    let progress: Double
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 130)
            Text(NSLocalizedString(label, comment: "Settings label")).font(.caption.weight(.medium)).lineLimit(1)
            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
}

private struct StoragePieSlice: View {
    let start: Double
    let end: Double
    let color: Color
    let label: String
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PieSlicePath(start: start, end: end)
                    .fill(color)
                    .overlay(PieSlicePath(start: start, end: end).stroke(Color.black.opacity(0.35), lineWidth: 1))
                let angle = (start + end) / 2 * 2 * .pi - .pi / 2
                let radius = min(geometry.size.width, geometry.size.height) * 0.36
                if fraction >= 0.035 {
                    Text(NSLocalizedString(label, comment: "Settings label"))
                        .font(.system(size: fraction < 0.06 ? 8 : 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: fraction < 0.06 ? 48 : 82)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .clipped()
                        .rotationEffect(.radians(angle + .pi / 2))
                        .position(x: geometry.size.width / 2 + cos(angle) * radius, y: geometry.size.height / 2 + sin(angle) * radius)
                }
            }
        }
    }
}

private struct PieSlicePath: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @State private var showingCustomConfig = false
    @ObservedObject private var appFetcher = SystemAppFetcher.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("General")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    SettingsSectionHeader(title: "Behavior")
                ForEach(GeneralSettingType.allCases) { setting in
                    IconToggleRow(systemImage: setting.systemImage, color: setting.iconColor, title: setting.displayName, isOn: binding(for: setting))
                    if setting == .expandOnHover, settings.settings.expandOnHover {
                        CustomSliderRowView(
                            label: "Hover Delay",
                            value: $settings.settings.expandOnHoverDelay,
                            range: 0.0...1.0,
                            specifier: "%.2fs"
                        )
                        .padding(.horizontal, 60)
                        .padding(.bottom, 8)
                    }
                    if setting != GeneralSettingType.allCases.last {
                        Divider().padding(.leading, 60)
                    }
                }
                if settings.settings.capsLockHorizontalLockEnabled {
                    Divider().padding(.leading, 60)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Allow in Apps")
                            .font(.headline)
                            .padding([.horizontal])
                        AppTogglesListView(
                            isEnabled: { app in capsLockAppBinding(for: app, isBrowser: app.isBrowser) },
                            maxHeight: 360,
                            browsersSectionTitle: "Browsers (Disabled by Default)",
                            onSelectAll: setAllApps
                        )
                    }
                    .padding()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }.modifier(SettingsContainerModifier())

                SettingsCard(title: "System") {

                    ToggleRow(title: "Launch at Login", description: "Start Sapphire automatically when you log in to your Mac.", isOn: $settings.settings.launchAtLogin)
                    Divider().padding(.leading, 20)

                    ToggleRow(title: "Enable Haptic Feedback", description: "Provide tactile feedback for certain interactions.", isOn: $settings.settings.hapticFeedbackEnabled)
                    Divider().padding(.leading, 20)

                    ToggleRow(title: "Hide from Screen Sharing", description: "Never include Sapphire in screen sharing, screenshots, or screen recordings.", isOn: $settings.settings.hideFromScreenSharing)
                    Divider().padding(.leading, 20)

                    ToggleRow(title: "Google Analytics", description: "Send anonymous usage events to Google to help improve Sapphire. Disable this to opt out of analytics collection.", isOn: $settings.settings.googleAnalyticsEnabled)
                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Swipe to Hide Notch",
                        description: "When the notch is collapsed, swipe up over it to hide it completely. Swipe down near the notch area to bring it back.",
                        isOn: $settings.settings.swipeToHideNotch
                    )
                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Don't Expand While Locked",
                        description: "Prevent hover, click, and swipe from expanding the notch while the Mac is locked.",
                        isOn: $settings.settings.preventNotchExpandWhenLocked
                    )
                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Show Notch On")
                        Spacer()
                        Picker("", selection: $settings.settings.notchDisplayTarget) {
                            ForEach(NotchDisplayTarget.allCases) { target in
                                Text(target.displayName).tag(target)
                            }
                        }.labelsHidden().frame(width: 200)
                    }.padding()

                    Text("Choose which display Sapphire should attach to when multiple screens are connected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom)

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Floating Island on Notchless Displays",
                        description: "Use a rounded island separated from the top edge on Macs and displays without a hardware notch.",
                        isOn: $settings.settings.floatingIslandOnNotchlessDisplays
                    )

                    if settings.settings.floatingIslandOnNotchlessDisplays {
                        Divider().padding(.leading, 20)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Island Top Offset")
                                Text("Distance from the top edge on notchless displays.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            DeferredValueEditor(value: $settings.settings.floatingIslandTopOffset.asDouble) { draft, onEditingChanged in
                                HStack(spacing: 8) {
                                    Slider(
                                        value: draft,
                                        in: 0...40,
                                        step: 1,
                                        onEditingChanged: onEditingChanged
                                    )
                                    .frame(width: 150)
                                    .accessibilityLabel("Island Top Offset")
                                    Text("\(Int(draft.wrappedValue)) pt")
                                        .monospacedDigit()
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }
                        }
                        .padding()
                    }

                }

                SettingsCard(title: "Widget Transitions", description: "Control the visual effects when switching between widgets inside the expanded notch.") {

                    Toggle("Enable Fade Effect", isOn: $settings.settings.enableWidgetSwitchFade)
                        .padding()
                    Divider().padding(.leading, 20)
                    Toggle("Enable Slide Effect", isOn: $settings.settings.enableWidgetSwitchSlide)
                        .padding()
                    Divider().padding(.leading, 20)
                    Toggle("Enable Bounce Effect", isOn: $settings.settings.enableWidgetSwitchBounce)
                        .padding()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Animation Profile")
                        .font(.headline)
                        .padding([.horizontal, .top])

                    Text(descriptionForCurrentProfile())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 5)

                    Picker("Animation Profile", selection: $settings.settings.animationProfile) {
                        ForEach(AnimationProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom)

                    if settings.settings.animationProfile == .custom {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Custom Animation Values")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button("Reset to Defaults") {
                                    withAnimation {
                                        settings.settings.customAnimationConfiguration = .init()
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .help("Reset all custom animation values to the 'Snappy' defaults.")
                            }

                            Text("Response: How long the animation takes (lower is faster).\nDamping: How much bounce (1.0 is no bounce).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 5)

                            Group {
                                Text("Main Transitions").font(.caption.bold()).foregroundColor(.secondary)
                                AnimationSliderRow(title: "Expand Response", description: "Opening the main widget view.", value: $settings.settings.customAnimationConfiguration.expandResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Expand Damping", description: "", value: $settings.settings.customAnimationConfiguration.expandDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Collapse Response", description: "Closing the main widget view.", value: $settings.settings.customAnimationConfiguration.collapseResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Collapse Damping", description: "", value: $settings.settings.customAnimationConfiguration.collapseDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Swipe Open Response", description: "Opening the widget with a trackpad swipe.", value: $settings.settings.customAnimationConfiguration.swipeOpenResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Swipe Open Damping", description: "", value: $settings.settings.customAnimationConfiguration.swipeOpenDamping, range: 0.4...1.0)
                            }

                            Group {
                                Text("Dynamic States").font(.caption.bold()).foregroundColor(.secondary).padding(.top)
                                AnimationSliderRow(title: "Hover Response", description: "The small expansion when hovering over the notch.", value: $settings.settings.customAnimationConfiguration.hoverResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Hover Damping", description: "", value: $settings.settings.customAnimationConfiguration.hoverDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Auto-Expand Response", description: "When a Live Activity appears automatically.", value: $settings.settings.customAnimationConfiguration.autoExpandResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Auto-Expand Damping", description: "", value: $settings.settings.customAnimationConfiguration.autoExpandDamping, range: 0.4...1.0)
                            }

                            Group {
                                Text("Content & Activities").font(.caption.bold()).foregroundColor(.secondary).padding(.top)
                                AnimationSliderRow(title: "Content Transition Response", description: "How widgets appear inside the expanded view.", value: $settings.settings.customAnimationConfiguration.contentTransitionResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Content Transition Damping", description: "", value: $settings.settings.customAnimationConfiguration.contentTransitionDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Activity Switch Response", description: "Transitioning between different Live Activities.", value: $settings.settings.customAnimationConfiguration.activityToActivityResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Activity Switch Damping", description: "", value: $settings.settings.customAnimationConfiguration.activityToActivityDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Activity Morph Response", description: "Smoothly changing the shape of a Live Activity.", value: $settings.settings.customAnimationConfiguration.activityMorphResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Activity Morph Damping", description: "", value: $settings.settings.customAnimationConfiguration.activityMorphDamping, range: 0.4...1.0)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.animationProfile)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Advanced Customization").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Enable Custom Notch Configuration", description: "Override default appearance and animation values. This may lead to unexpected behavior.", isOn: $settings.settings.useCustomNotchConfiguration)

                    if settings.settings.useCustomNotchConfiguration {
                        Button("Edit Custom Configuration") {
                            showingCustomConfig = true
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.useCustomNotchConfiguration)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Notch Bar Items").font(.headline).padding([.horizontal, .top])
                    Text("Enable, disable, and reorder the icons that appear when you expand the notch.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    ReorderableVStack(items: $settings.settings.notchButtonOrder) { buttonType in
                        NotchButtonRowView(buttonType: buttonType)
                    }
                }
                .modifier(SettingsContainerModifier())

            }
        .padding(25)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
        if settings.settings.capsLockHorizontalLockEnabled {
            appFetcher.fetchApps()
        }
    }
    .onChange(of: settings.settings.capsLockHorizontalLockEnabled) { _, enabled in
        if enabled {
            appFetcher.fetchApps()
        } else {
            SystemAppFetcher.shared.releaseCachedApps()
            AppIconLoader.releaseCache()
        }
    }
    .sheet(isPresented: $showingCustomConfig) {
            CustomNotchConfigView(config: $settings.settings.customNotchConfiguration)
        }
    }

    private func binding(for setting: GeneralSettingType) -> Binding<Bool> {
        switch setting {
        case .expandOnHover: return $settings.settings.expandOnHover
        case .swipeToSwitchWidgets: return $settings.settings.swipeToSwitchWidgets
        case .enableOpeningBounce: return $settings.settings.enableOpeningBounce
        case .capsLockHorizontalLock: return $settings.settings.capsLockHorizontalLockEnabled
        }
    }

    private func capsLockAppBinding(for app: SystemApp, isBrowser: Bool) -> Binding<Bool> {
        Binding(
            get: { settings.settings.capsLockHorizontalLockAppStates[app.id, default: true] },
            set: { settings.settings.capsLockHorizontalLockAppStates[app.id] = $0 }
        )
    }

    private func setAllApps(to enabled: Bool) {
        var appStates = settings.settings.capsLockHorizontalLockAppStates
        appStates.reserveCapacity(appFetcher.apps.count)
        for app in appFetcher.apps {
            appStates[app.id] = enabled
        }
        settings.settings.capsLockHorizontalLockAppStates = appStates
    }

    private func descriptionForCurrentProfile() -> String {
        switch settings.settings.animationProfile {
        case .snappy:
            return "The default. A quick and responsive feel with minimal bounce."
        case .bouncy:
            return "A playful and energetic animation with noticeable bounce."
        case .calm:
            return "A slower, more graceful animation with a very gentle ease."
        case .custom:
            return "Fine-tune every animation parameter to your exact liking."
        }
    }
}

fileprivate struct AnimationSliderRow: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        DeferredValueEditor(value: $value) { draft, onEditingChanged in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString(title, comment: "Settings title"))
                        if !description.isEmpty {
                            Text(NSLocalizedString(description, comment: "Settings description"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(String(format: "%.2f", draft.wrappedValue))
                        .font(.body.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Slider(value: draft, in: range, onEditingChanged: onEditingChanged)
            }
        }
        .padding(.vertical, 8)
    }
}

struct CustomNotchConfigView: View {
    @Binding var config: CustomizableNotchConfiguration
    @Environment(\.dismiss) var dismiss

    @State private var initialCornerRadius: Double
    @State private var topBuffer: Double
    @State private var scaleFactor: Double
    @State private var hoverExpandedCornerRadius: Double
    @State private var autoExpandedCornerRadius: Double
    @State private var autoExpandedTallHeight: Double
    @State private var autoExpandedContentVerticalPadding: Double
    @State private var clickExpandedCornerRadius: Double
    @State private var liveActivityBottomCornerRadius: Double
    @State private var collapseAnimationDelay: Double
    @State private var dragActivationCollapseDelay: Double
    @State private var expandAnimationResponse: Double
    @State private var expandAnimationDamping: Double
    @State private var swipeOpenAnimationResponse: Double
    @State private var swipeOpenAnimationDamping: Double
    @State private var collapseAnimationResponse: Double
    @State private var collapseAnimationDamping: Double
    @State private var widgetBlurRadiusMax: Double
    @State private var activityBlurRadiusMax: Double
    @State private var expandedShadowRadius: Double
    @State private var expandedShadowOffsetY: Double
    @State private var contentTopPadding: Double
    @State private var contentBottomPadding: Double
    @State private var contentHorizontalPadding: Double

    init(config: Binding<CustomizableNotchConfiguration>) {
        self._config = config
        let wrapped = config.wrappedValue

        _initialCornerRadius = State(initialValue: Double(wrapped.initialCornerRadius))
        _topBuffer = State(initialValue: Double(wrapped.topBuffer))
        _scaleFactor = State(initialValue: Double(wrapped.scaleFactor))
        _hoverExpandedCornerRadius = State(initialValue: Double(wrapped.hoverExpandedCornerRadius))
        _autoExpandedCornerRadius = State(initialValue: Double(wrapped.autoExpandedCornerRadius))
        _autoExpandedTallHeight = State(initialValue: Double(wrapped.autoExpandedTallHeight))
        _autoExpandedContentVerticalPadding = State(initialValue: Double(wrapped.autoExpandedContentVerticalPadding))
        _clickExpandedCornerRadius = State(initialValue: Double(wrapped.clickExpandedCornerRadius))
        _liveActivityBottomCornerRadius = State(initialValue: Double(wrapped.liveActivityBottomCornerRadius))
        _collapseAnimationDelay = State(initialValue: wrapped.collapseAnimationDelay)
        _dragActivationCollapseDelay = State(initialValue: wrapped.dragActivationCollapseDelay)
        _expandAnimationResponse = State(initialValue: wrapped.expandAnimationResponse)
        _expandAnimationDamping = State(initialValue: wrapped.expandAnimationDamping)
        _swipeOpenAnimationResponse = State(initialValue: wrapped.swipeOpenAnimationResponse)
        _swipeOpenAnimationDamping = State(initialValue: wrapped.swipeOpenAnimationDamping)
        _collapseAnimationResponse = State(initialValue: wrapped.collapseAnimationResponse)
        _collapseAnimationDamping = State(initialValue: wrapped.collapseAnimationDamping)
        _widgetBlurRadiusMax = State(initialValue: Double(wrapped.widgetBlurRadiusMax))
        _activityBlurRadiusMax = State(initialValue: Double(wrapped.activityBlurRadiusMax))
        _expandedShadowRadius = State(initialValue: Double(wrapped.expandedShadowRadius))
        _expandedShadowOffsetY = State(initialValue: Double(wrapped.expandedShadowOffsetY))
        _contentTopPadding = State(initialValue: Double(wrapped.contentTopPadding))
        _contentBottomPadding = State(initialValue: Double(wrapped.contentBottomPadding))
        _contentHorizontalPadding = State(initialValue: Double(wrapped.contentHorizontalPadding))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Notch Configuration")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 25) {
                    Section(header: Text("Sizing & Position").font(.headline)) {
                        CustomSliderRowView(label: "Auto-Expanded Height", value: $autoExpandedTallHeight, range: 50...150, specifier: "%.1f")
                        CustomSliderRowView(label: "Top Buffer", value: $topBuffer, range: 0...20, specifier: "%.1f")
                    }

                    Section(header: Text("Hover State").font(.headline)) {
                        CustomSliderRowView(label: "Hover Scale Factor", value: $scaleFactor, range: 1.0...1.5, specifier: "%.2f x")
                    }

                    Section(header: Text("Corner Radii").font(.headline)) {
                        CustomSliderRowView(label: "Initial", value: $initialCornerRadius, range: 5...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Hover-Expanded", value: $hoverExpandedCornerRadius, range: 10...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Auto-Expanded", value: $autoExpandedCornerRadius, range: 10...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Click-Expanded", value: $clickExpandedCornerRadius, range: 10...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Live Activity Bottom", value: $liveActivityBottomCornerRadius, range: 10...60, specifier: "%.1f")
                    }

                    Section(header: Text("Animation (Springs)").font(.headline)) {
                        CustomSliderRowView(label: "Expand Response", value: $expandAnimationResponse, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Expand Damping", value: $expandAnimationDamping, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Swipe Open Response", value: $swipeOpenAnimationResponse, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Swipe Open Damping", value: $swipeOpenAnimationDamping, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Collapse Response", value: $collapseAnimationResponse, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Collapse Damping", value: $collapseAnimationDamping, range: 0.1...1.0, specifier: "%.2f")
                    }

                    Section(header: Text("Delays").font(.headline)) {
                        CustomSliderRowView(label: "Collapse Animation Delay", value: $collapseAnimationDelay, range: 0.0...1.0, specifier: "%.2f s")
                        CustomSliderRowView(label: "Drag Activation Collapse Delay", value: $dragActivationCollapseDelay, range: 0.0...1.0, specifier: "%.2f s")
                    }

                    Section(header: Text("Padding").font(.headline)) {
                        CustomSliderRowView(label: "Content Top Padding", value: $contentTopPadding, range: 0...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Content Bottom Padding", value: $contentBottomPadding, range: 0...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Content Horizontal Padding", value: $contentHorizontalPadding, range: 0...100, specifier: "%.1f")
                        CustomSliderRowView(label: "Auto-Expanded Vertical Padding", value: $autoExpandedContentVerticalPadding, range: 0...50, specifier: "%.1f")
                    }

                    Section(header: Text("Blur & Shadow").font(.headline)) {
                        CustomSliderRowView(label: "Widget Blur Radius Max", value: $widgetBlurRadiusMax, range: 0...100, specifier: "%.1f")
                        CustomSliderRowView(label: "Activity Blur Radius Max", value: $activityBlurRadiusMax, range: 0...100, specifier: "%.1f")
                        CustomSliderRowView(label: "Expanded Shadow Radius", value: $expandedShadowRadius, range: 0...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Expanded Shadow Offset Y", value: $expandedShadowOffsetY, range: 0...30, specifier: "%.1f")
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    let defaultConfig = CustomizableNotchConfiguration()
                    syncState(from: defaultConfig)
                }
                Spacer()
                Button("Done") {
                    syncConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 550, idealWidth: 600, minHeight: 400, idealHeight: 750)
    }

    private func syncState(from sourceConfig: CustomizableNotchConfiguration) {
        initialCornerRadius = Double(sourceConfig.initialCornerRadius)
        topBuffer = Double(sourceConfig.topBuffer)
        scaleFactor = Double(sourceConfig.scaleFactor)
        hoverExpandedCornerRadius = Double(sourceConfig.hoverExpandedCornerRadius)
        autoExpandedCornerRadius = Double(sourceConfig.autoExpandedCornerRadius)
        autoExpandedTallHeight = Double(sourceConfig.autoExpandedTallHeight)
        autoExpandedContentVerticalPadding = Double(sourceConfig.autoExpandedContentVerticalPadding)
        clickExpandedCornerRadius = Double(sourceConfig.clickExpandedCornerRadius)
        liveActivityBottomCornerRadius = Double(sourceConfig.liveActivityBottomCornerRadius)
        collapseAnimationDelay = sourceConfig.collapseAnimationDelay
        dragActivationCollapseDelay = sourceConfig.dragActivationCollapseDelay
        expandAnimationResponse = sourceConfig.expandAnimationResponse
        expandAnimationDamping = sourceConfig.expandAnimationDamping
        swipeOpenAnimationResponse = sourceConfig.swipeOpenAnimationResponse
        swipeOpenAnimationDamping = sourceConfig.swipeOpenAnimationDamping
        collapseAnimationResponse = sourceConfig.collapseAnimationResponse
        collapseAnimationDamping = sourceConfig.collapseAnimationDamping
        widgetBlurRadiusMax = Double(sourceConfig.widgetBlurRadiusMax)
        activityBlurRadiusMax = Double(sourceConfig.activityBlurRadiusMax)
        expandedShadowRadius = Double(sourceConfig.expandedShadowRadius)
        expandedShadowOffsetY = Double(sourceConfig.expandedShadowOffsetY)
        contentTopPadding = Double(sourceConfig.contentTopPadding)
        contentBottomPadding = Double(sourceConfig.contentBottomPadding)
        contentHorizontalPadding = Double(sourceConfig.contentHorizontalPadding)
    }

    private func syncConfig() {
        config.initialCornerRadius = CGFloat(initialCornerRadius)
        config.topBuffer = CGFloat(topBuffer)
        config.scaleFactor = CGFloat(scaleFactor)
        config.hoverExpandedCornerRadius = CGFloat(hoverExpandedCornerRadius)
        config.autoExpandedCornerRadius = CGFloat(autoExpandedCornerRadius)
        config.autoExpandedTallHeight = CGFloat(autoExpandedTallHeight)
        config.autoExpandedContentVerticalPadding = CGFloat(autoExpandedContentVerticalPadding)
        config.clickExpandedCornerRadius = CGFloat(clickExpandedCornerRadius)
        config.liveActivityBottomCornerRadius = CGFloat(liveActivityBottomCornerRadius)
        config.collapseAnimationDelay = collapseAnimationDelay
        config.dragActivationCollapseDelay = dragActivationCollapseDelay
        config.expandAnimationResponse = expandAnimationResponse
        config.expandAnimationDamping = expandAnimationDamping
        config.swipeOpenAnimationResponse = swipeOpenAnimationResponse
        config.swipeOpenAnimationDamping = swipeOpenAnimationDamping
        config.collapseAnimationResponse = collapseAnimationResponse
        config.collapseAnimationDamping = collapseAnimationDamping
        config.widgetBlurRadiusMax = CGFloat(widgetBlurRadiusMax)
        config.activityBlurRadiusMax = CGFloat(activityBlurRadiusMax)
        config.expandedShadowRadius = CGFloat(expandedShadowRadius)
        config.expandedShadowOffsetY = CGFloat(expandedShadowOffsetY)
        config.contentTopPadding = CGFloat(contentTopPadding)
        config.contentBottomPadding = CGFloat(contentBottomPadding)
        config.contentHorizontalPadding = CGFloat(contentHorizontalPadding)
    }
}

struct FileShelfSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var continuity = ContinuityManager.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("File Shelf")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Expand Shelf on Hover",
                        description: "Automatically expand the full File Shelf by hovering over its live activity.",
                        isOn: $settings.settings.hoverToOpenFileShelf
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Open Shelf on Live Activity Click",
                        description: "Clicking the File Shelf live activity opens the shelf instead of the default widgets.",
                        isOn: $settings.settings.clickToOpenFileShelf
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Remove File After Drag Out",
                        description: "When you drag a file out of the shelf, remove it from the shelf automatically.",
                        isOn: $settings.settings.removeFileFromShelfAfterDrag
                    )
                }
                .modifier(SettingsContainerModifier())

                SettingsCard(
                    title: "Drop Destinations",
                    description: "Choose which destinations appear when you drag files into the notch."
                ) {
                    ToggleRow(
                        title: "AirDrop",
                        description: "Show the AirDrop box in the File Shelf landing view.",
                        isOn: $settings.settings.fileShelfAirDropDestinationEnabled
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Share to Devices",
                        description: deviceDestinationDescription,
                        isOn: $settings.settings.fileShelfDeviceDestinationsEnabled
                    )
                }
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var deviceDestinationDescription: String {
        let count = continuity.peers.count
        if count == 0 {
            return "Show a same-size card for your paired Continuity devices. Pair a device in Continuity settings to make it available."
        }
        return "Show all \(count) paired \(count == 1 ? "device" : "devices") in an adaptive, same-size sharing card. Offline devices stay visible."
    }
}

struct NotesSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Notes")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Enable Notes Widget",
                        description: "Show the quick notes widget in the notch widget strip.",
                        isOn: $settings.settings.notesWidgetEnabled
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Open Notes on Click",
                        description: "Clicking the notes widget expands into the full notes editor.",
                        isOn: $settings.settings.notesOpenOnClick
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Show Notes in Notch Bar",
                        description: "Add a notes icon to the expanded notch header for quick access.",
                        isOn: $settings.settings.notesIconEnabled
                    )
                }
                .modifier(SettingsContainerModifier())

                SettingsCard(title: "Swipe Actions", description: "Customize what happens when you swipe a note row left or right in the full notes view.") {

                    SwipeActionPickerRow(
                        title: "Swipe Right",
                        description: "Leading swipe on a note row.",
                        selection: $settings.settings.swipeActionSettings.notesLeading,
                        options: NotesSwipeAction.allCases,
                        label: { $0.displayName }
                    )

                    Divider().padding(.leading, 20)

                    SwipeActionPickerRow(
                        title: "Swipe Left",
                        description: "Trailing swipe on a note row.",
                        selection: $settings.settings.swipeActionSettings.notesTrailing,
                        options: NotesSwipeAction.allCases,
                        label: { $0.displayName }
                    )
                }
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct ClipboardSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @State private var historyCount = 0
    @ObservedObject private var shortcutRecorder = GlobalShortcutRecorder.shared
    @ObservedObject private var clipboardPickerManager = ClipboardPickerManager.shared

    private var isRecordingPickerShortcut: Bool {
        shortcutRecorder.isRecording && shortcutRecorder.recordingIdentifier == "clipboardPickerShortcut"
    }

    private var pickerShortcutLabel: String {
        let shortcut = settings.settings.clipboardPickerShortcut
        return "\(KeyboardShortcutHelper.description(for: shortcut.modifiers))\(shortcut.key)"
    }

    private var quickPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PremiumFeatureView(feature: .clipboardPicker) {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsSectionHeader(title: "Quick Picker", description: "Open the unified Sapphire picker right where you're typing with a global shortcut. Selecting a clipboard item copies it and pastes it at the cursor; the Emoji tab types emoji directly. (The emoji shortcut opens the same panel on its Emoji tab.)")

                    ToggleRow(
                        title: "Enable Quick Picker",
                        description: "Allow the global shortcut to open the clipboard panel anywhere.",
                        isOn: $settings.settings.clipboardPickerEnabled
                    )

                    Divider().padding(.leading, 20)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Picker Shortcut")
                                .font(.system(size: 14, weight: .medium))
                            Text("Replaces the default paste-and-match-style shortcut.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        if !isRecordingPickerShortcut {
                            Text(pickerShortcutLabel)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }

                        Button(isRecordingPickerShortcut ? "Cancel" : "Record…") {
                            if isRecordingPickerShortcut {
                                shortcutRecorder.stopRecording()
                            } else {
                                shortcutRecorder.startRecording(identifier: "clipboardPickerShortcut") { key, modifiers in
                                    settings.settings.clipboardPickerShortcut = KeyboardShortcut(key: key, modifiers: modifiers)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!settings.settings.clipboardPickerEnabled)
                    }
                    .padding()

                    Divider().padding(.leading, 20)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Picker")
                                .font(.system(size: 14, weight: .medium))
                            Text("Try the picker right now — it opens on the Clipboard tab.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            clipboardPickerManager.presentPicker()
                        } label: {
                            Label("Open Picker", systemImage: "list.clipboard")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .disabled(!settings.settings.clipboardPickerEnabled)
                    }
                    .padding()
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Clipboard")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                RequiredPermissionsView(section: .clipboard)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Enable Clipboard Widget",
                        description: "Show recent clipboard items in the notch widget strip.",
                        isOn: $settings.settings.clipboardWidgetEnabled
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Open Clipboard on Click",
                        description: "Clicking the clipboard widget expands into the full clipboard history.",
                        isOn: $settings.settings.clipboardOpenOnClick
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Show Clipboard in Notch Bar",
                        description: "Add a clipboard icon to the expanded notch header for quick access.",
                        isOn: $settings.settings.clipboardIconEnabled
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Monitor Clipboard",
                        description: "Continuously capture newly copied text and images into Sapphire history.",
                        isOn: $settings.settings.clipboardMonitoringEnabled
                    )
                    .onChange(of: settings.settings.clipboardMonitoringEnabled) { _, enabled in
                        settings.commitNow()
                        if enabled {
                            ClipboardManager.shared.startMonitoring()
                        } else {
                            ClipboardManager.shared.stopMonitoring()
                        }
                    }
                }
                .modifier(SettingsContainerModifier())

                quickPickerSection

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Unlimited History",
                        description: "Keep every clipboard item Sapphire captures with no retention cap.",
                        isOn: $settings.settings.clipboardHistoryUnlimited
                    )
                    .onChange(of: settings.settings.clipboardHistoryUnlimited) { _, unlimited in
                        if unlimited {
                            settings.settings.clipboardHistoryLimit = 0
                        } else if settings.settings.clipboardHistoryLimit <= 0 {
                            settings.settings.clipboardHistoryLimit = 40
                        }
                    }

                    if !settings.settings.clipboardHistoryUnlimited {
                        Divider().padding(.leading, 20)

                        CustomSliderRowView(
                            label: "History Limit",
                            value: Binding(
                                get: { Double(max(4, settings.settings.clipboardHistoryLimit)) },
                                set: { settings.settings.clipboardHistoryLimit = Int($0.rounded()) }
                            ),
                            range: 4...200,
                            specifier: "%.0f items"
                        )
                    }

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Ignore Concealed Items",
                        description: "Skip passwords and other concealed clipboard content (e.g., from 1Password, Bitwarden).",
                        isOn: $settings.settings.clipboardIgnoreConcealedItems
                    )

                    Divider().padding(.leading, 20)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear History")
                            Text("Remove \(historyCount) stored clipboard items.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Clear") {
                            ClipboardManager.shared.clearHistory()
                            historyCount = 0
                        }
                        .buttonStyle(.bordered)
                        .disabled(historyCount == 0)
                    }
                    .padding()
                }
                .modifier(SettingsContainerModifier())

                SettingsCard(title: "Swipe Actions", description: "Customize what happens when you swipe a clipboard row left or right in the full clipboard view.") {

                    SwipeActionPickerRow(
                        title: "Swipe Right",
                        description: "Leading swipe on a clipboard row.",
                        selection: $settings.settings.swipeActionSettings.clipboardLeading,
                        options: ClipboardSwipeAction.allCases,
                        label: { $0.displayName }
                    )

                    Divider().padding(.leading, 20)

                    SwipeActionPickerRow(
                        title: "Swipe Left",
                        description: "Trailing swipe on a clipboard row.",
                        selection: $settings.settings.swipeActionSettings.clipboardTrailing,
                        options: ClipboardSwipeAction.allCases,
                        label: { $0.displayName }
                    )
                }

                VStack(alignment: .leading, spacing: 0) {
                    PremiumFeatureView(feature: .clipboardAdvancedTools) {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsSectionHeader(title: "Auto-Clear Clipboard", description: "Empty the system clipboard a set time after copying, or when the Mac sleeps or the screen locks. Saved history items are never touched.")

                            ToggleRow(
                                title: "Enable Auto-Clear",
                                description: "Work with or without clipboard history enabled.",
                                isOn: $settings.settings.clipboardAutoClearEnabled
                            )

                            if settings.settings.clipboardAutoClearEnabled {
                                Divider().padding(.leading, 20)

                                ToggleRow(
                                    title: "Clear After a Delay",
                                    description: "Empty the clipboard this long after you copy something.",
                                    isOn: Binding(
                                        get: { settings.settings.clipboardAutoClearInterval > 0 },
                                        set: { on in
                                            if on, settings.settings.clipboardAutoClearInterval <= 0 {
                                                settings.settings.clipboardAutoClearInterval = 30
                                            } else if !on {
                                                settings.settings.clipboardAutoClearInterval = 0
                                            }
                                        }
                                    )
                                )

                                if settings.settings.clipboardAutoClearInterval > 0 {
                                    Divider().padding(.leading, 20)
                                    CustomSliderRowView(
                                        label: "Clear After",
                                        value: $settings.settings.clipboardAutoClearInterval,
                                        range: 5...300,
                                        specifier: "%.0f s"
                                    )
                                    .padding(.horizontal)
                                }

                                Divider().padding(.leading, 20)
                                ToggleRow(
                                    title: "Clear When Mac Sleeps",
                                    description: "Empty the clipboard when the Mac (or its display) sleeps.",
                                    isOn: $settings.settings.clipboardAutoClearOnSleep
                                )

                                Divider().padding(.leading, 20)
                                ToggleRow(
                                    title: "Clear When Screen Locks",
                                    description: "Empty the clipboard when the screen locks.",
                                    isOn: $settings.settings.clipboardAutoClearOnLock
                                )
                            }
                        }
                    }
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    PremiumFeatureView(feature: .clipboardAdvancedTools) {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsSectionHeader(title: "Clean URL", description: "Strip tracking parameters (utm_*, fbclid, gclid, …) from copied links automatically. Images, files and rich text pass through untouched.")

                            ToggleRow(
                                title: "Clean Copied Links",
                                description: "Rewrite copied URLs without their tracking parameters.",
                                isOn: $settings.settings.clipboardCleanURLEnabled
                            )

                            if settings.settings.clipboardCleanURLEnabled {
                                Divider().padding(.leading, 20)
                                ToggleRow(
                                    title: "Clean Automatically on Copy",
                                    description: "Clean as soon as a link is copied. Turn off to only clean from the picker.",
                                    isOn: $settings.settings.clipboardCleanURLAutoClean
                                )
                            }
                        }
                    }
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    PremiumFeatureView(feature: .clipboardAdvancedTools) {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsSectionHeader(title: "Finder Cut & Paste", description: "⌘X then ⌘V moves copied files instead of copying them, ⌘V pastes copied images as PNG files into the front Finder folder, and F2 renames the selected item.")

                            ToggleRow(
                                title: "Enable Finder Shortcuts",
                                description: "Active only while Finder is the app in front.",
                                isOn: $settings.settings.clipboardFinderCutPasteEnabled
                            )

                            if settings.settings.clipboardFinderCutPasteEnabled {
                                Divider().padding(.leading, 20)
                                ToggleRow(
                                    title: "Paste Images as PNG Files",
                                    description: "⌘V in Finder turns a copied image into a PNG file in the front folder.",
                                    isOn: $settings.settings.clipboardFinderPasteImagesAsPNG
                                )

                                Divider().padding(.leading, 20)
                                ToggleRow(
                                    title: "F2 Renames the Selection",
                                    description: "Press F2 in Finder to start an inline rename.",
                                    isOn: $settings.settings.clipboardFinderF2RenameEnabled
                                )
                            }
                        }
                    }
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    PremiumFeatureView(feature: .clipboardAdvancedTools) {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsSectionHeader(title: "Text Snippets", description: "Type a short trigger anywhere and it becomes your text. Use \"{{date}}\", \"{{time}}\", \"{{date:MMMM d}}\" or \"{{clipboard}}\" in the replacement. Sapphire never expands while you type inside Sapphire itself.")

                            ToggleRow(
                                title: "Enable Text Snippets",
                                description: "Expand triggers as you type in any app.",
                                isOn: $settings.settings.snippetsEnabled
                            )

                            if settings.settings.snippetsEnabled {
                                Divider().padding(.leading, 20)
                                ToggleRow(
                                    title: "Expand After Space or Punctuation",
                                    description: "Off expands the moment the trigger completes.",
                                    isOn: $settings.settings.snippetsExpandAfterSpace
                                )

                                Divider().padding(.leading, 20)
                                HStack {
                                    Text("Snippets").font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        settings.settings.snippetsList.append(SnippetEntry())
                                    } label: {
                                        Label("Add Snippet", systemImage: "plus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal)

                                ForEach($settings.settings.snippetsList) { $snippet in
                                    Divider().padding(.leading, 20)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Toggle("", isOn: $snippet.isEnabled)
                                                .toggleStyle(.switch)
                                                .controlSize(.small)
                                            TextField("Trigger", text: $snippet.trigger)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 150)
                                            Spacer()
                                            Button {
                                                let doomed = snippet.id
                                                DispatchQueue.main.async {
                                                    settings.settings.snippetsList.removeAll { $0.id == doomed }
                                                }
                                            } label: {
                                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        TextField("Replacement text…", text: $snippet.replacement, axis: .vertical)
                                            .textFieldStyle(.roundedBorder)
                                            .lineLimit(1...4)
                                    }
                                    .padding(.horizontal)
                                }

                                if settings.settings.snippetsList.isEmpty {
                                    Text("No snippets yet — add one, then type its trigger in any app.")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal)
                                        .padding(.bottom, 6)
                                }
                            }
                        }
                    }
                }
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { historyCount = ClipboardManager.shared.recentItems.count }
    }
}

struct MirrorSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Mirror")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Enable Mirror Widget",
                        description: "Show the live camera feed widget in the notch widget strip.",
                        isOn: $settings.settings.mirrorWidgetEnabled
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Open Mirror on Click",
                        description: "Clicking the mirror widget expands into the full camera view.",
                        isOn: $settings.settings.mirrorOpenOnClick
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Flip Horizontally",
                        description: "Mirror the camera feed horizontally for a natural selfie view.",
                        isOn: $settings.settings.mirrorFlipHorizontally
                    )

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Camera Rotation")
                        Spacer()
                        Picker("", selection: $settings.settings.mirrorRotationMode) {
                            ForEach(MirrorRotationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    .padding()

                    Text("Automatically matches the orientation reported by the camera. If an external camera feed appears rotated, choose a fixed angle to display it upright.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                }
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct CaffeineSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Caffeinate")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Show Caffeinate in Notch Bar",
                        description: "Add a caffeinate toggle to the expanded notch header.",
                        isOn: $settings.settings.caffeinateEnabled
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Prevent Sleep in Clamshell Mode",
                        description: "Keep your Mac awake while Sapphire's caffeinate mode is active, even with the lid closed.",
                        isOn: $settings.settings.sleepInClamshell
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Keep Caffeinate Enabled After Clamshell",
                        description: "Continue preventing sleep after leaving clamshell mode instead of turning caffeinate off automatically.",
                        isOn: $settings.settings.persistentCaffeinateAfterClamshell
                    )

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Auto-Off Timeout")
                        Spacer()
                        Picker("", selection: $settings.settings.caffeinateTimeoutMinutes) {
                            Text("Never").tag(0.0)
                            Text("15 minutes").tag(15.0)
                            Text("30 minutes").tag(30.0)
                            Text("1 hour").tag(60.0)
                            Text("2 hours").tag(120.0)
                            Text("4 hours").tag(240.0)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    .padding()

                    Text("Automatically turn caffeinate off after the selected duration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                }
                .modifier(SettingsContainerModifier())

                CaffeineAutoTaskSettingsView()

                LidAngleCaffeineSettingsView()
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct WidgetsSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    private var enabledWidgetCount: Int {
        settings.settings.enabledWidgetTypes.count
    }

    var body: some View {
        let lockedWidgetTypes = Set(WidgetType.allCases.filter { type in
            type.requiredPremiumFeature
                .map { !subscriptionManager.hasAccess(to: $0) } ?? false
        })

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Widgets").font(.largeTitle.bold()).padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Behavior").font(.headline).padding([.top, .horizontal])
                    ToggleRow(
                        title: "Remember Last Open Menu",
                        description: "When re-opening the notch, it will return to the last menu you had open.",
                        isOn: $settings.settings.rememberLastMenu
                    )
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Hide Music Widget", description: "Hide music widget if no media is playing", isOn: $settings.settings.hideMusicWidgetWhenNotPlaying)
                    ToggleRow(title: "Hide Paused Spotify Song", description: "Hide the music widget when Spotify is paused and no other system media is playing", isOn: $settings.settings.hideMusicWidgetWhenSpotifyPausedAndIdle)
                    ToggleRow(title: "Persist Music Widget", description: "Keep the music widget visible with the last track even when playback is paused or stopped", isOn: $settings.settings.persistMusicWidgetWhenPaused)
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Appearance").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Dividers Between Widgets", description: "Display a subtle line separating each widget.", isOn: $settings.settings.showDividersBetweenWidgets)
                    ToggleRow(
                        title: "Ignore Widget Space Limit",
                        description: "Allow any widget to be enabled even when Sapphire estimates there is not enough notch space.",
                        isOn: $settings.settings.bypassWidgetSpaceLimit
                    )
                }
                .modifier(SettingsContainerModifier())

                if settings.settings.shopifyWidgetEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Shopify Orders").font(.headline).padding([.horizontal, .top])
                        Text("Connect a Shopify custom app with read_orders access. The Admin API token is stored in the macOS Keychain.").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                        TextField("Store domain (example.myshopify.com)", text: Binding(get: { APIKeyManager.shared.shopifyStoreDomain }, set: { APIKeyManager.shared.shopifyStoreDomain = $0 })).textFieldStyle(.roundedBorder).padding(.horizontal)
                        SecureField("Admin API access token", text: Binding(get: { APIKeyManager.shared.shopifyAdminToken }, set: { APIKeyManager.shared.shopifyAdminToken = $0 })).textFieldStyle(.roundedBorder).padding(.horizontal)
                        Text("Create it in Shopify Admin → Settings → Apps and sales channels → Develop apps, with read_orders permission.").font(.caption2).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
                    }
                    .modifier(SettingsContainerModifier())
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Widget Visibility & Order").font(.headline).padding([.horizontal, .top])
                    Text("Enable, disable, and reorder the widgets that appear in the notch. Space is limited by your display width.")
                        .font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    ReorderableVStack(items: $settings.settings.widgetOrder) { widget in
                        WidgetRowView(
                            widgetType: widget,
                            enabledWidgetCount: enabledWidgetCount,
                            isPremiumLocked: lockedWidgetTypes.contains(widget)
                        )
                    }
                    .modifier(SettingsContainerModifier())
                }
                if settings.settings.aiUsageWidgetEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Usage").font(.headline)
                        Text("Shows official subscription quota or third-party balances from the configured provider.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Automatic Refresh", selection: $settings.settings.aiUsageRefreshMinutes) {
                            Text("Every 5 minutes").tag(5)
                            Text("Every 15 minutes").tag(15)
                            Text("Every 30 minutes").tag(30)
                        }
                        Text("Quota reset times come from each provider. Manual refresh also respects the minimum request interval and rate-limit cooldown.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .modifier(SettingsContainerModifier())
                    ThirdPartyUsageSettingsView(configuration: $settings.settings.codexUsageQuery, provider: .codex)
                    ThirdPartyUsageSettingsView(configuration: $settings.settings.claudeUsageQuery, provider: .claude)
                }
            }
            .padding(25)
        }
    }
}

struct LiveActivitiesSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var availableSensors: [any Sensor_p] = []

    private enum PersistentActivitySelection: String, CaseIterable, Identifiable {
        case none = "None"
        case stats = "Stats"
        case battery = "Battery"
        case weather = "Weather"
        var id: String { self.rawValue }
    }

    private var currentPersistentActivity: PersistentActivitySelection {
        if settings.settings.showPersistentStatsLiveActivity {
            return .stats
        } else if settings.settings.showPersistentBatteryLiveActivity {
            return .battery
        } else if settings.settings.showPersistentWeatherLiveActivity {
            return .weather
        } else {
            return .none
        }
    }

    private var persistentActivityBinding: Binding<PersistentActivitySelection> {
        Binding(
            get: { currentPersistentActivity },
            set: { newValue in
                guard currentPersistentActivity != newValue else { return }
                var updated = settings.settings
                updated.showPersistentStatsLiveActivity = (newValue == .stats)
                updated.showPersistentBatteryLiveActivity = (newValue == .battery)
                updated.showPersistentWeatherLiveActivity = (newValue == .weather)
                settings.settings = updated
            }
        )
    }

    private func hideInFullScreenBinding(for type: LiveActivityType) -> Binding<Bool> {
        return Binding(
            get: { settings.settings.hideActivitiesInFullScreen[type.rawValue, default: false] },
            set: { settings.settings.hideActivitiesInFullScreen[type.rawValue] = $0 }
        )
    }

    private func binding(for statType: StatType) -> Binding<StatThreshold> {
        return Binding(
            get: { settings.settings.statThresholds[statType, default: StatThreshold()] },
            set: { settings.settings.statThresholds[statType] = $0 }
        )
    }

    var body: some View {
        let lockedActivityTypes = Set(LiveActivityType.allCases.filter { type in
            type.requiredPremiumFeature
                .map { !subscriptionManager.hasAccess(to: $0) } ?? false
        })

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Live Activities").font(.largeTitle.bold()).padding(.bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Text("General Behavior").font(.headline).padding([.top, .horizontal])
                    ToggleRow(
                          title: "Show compact focus live activity text",
                          description: "Instead of showing the full focus name, only on/off.",
                          isOn: Binding(
                              get: { settings.settings.focusDisplayMode == .compact },
                              set: { settings.settings.focusDisplayMode = $0 ? .compact : .full }
                          )
                      )

                    ToggleRow(
                          title: "Show compact battery live activity",
                          description: "Instead of showing the full state, only show icon.",
                          isOn: Binding(
                            get: { settings.settings.batteryNotificationStyle == .compact },
                            set: { settings.settings.batteryNotificationStyle = $0 ? .compact : .default }
                          )
                      )
                    ToggleRow(title: "Swipe to Dismiss", description: "Swipe down on a live activity to dismiss it.", isOn: $settings.settings.swipeToDismissLiveActivity)
                    Divider().padding(.leading, 20)
                    ToggleRow(
                        title: "Hide When Source App is Active",
                        description: "Automatically hide the music live activity when Spotify or Music is the frontmost app.",
                        isOn: $settings.settings.hideLiveActivityWhenSourceActive
                    )
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Hide All in Full Screen", description: "Automatically hide all live activities when an app is in full screen.", isOn: $settings.settings.hideLiveActivityInFullScreen)

                    DisclosureGroup("Advanced: Hide Specific Activities in Full Screen") {
                        VStack(spacing: 0) {
                            ForEach(LiveActivityType.allCases) { activityType in
                                Toggle(activityType.displayName, isOn: hideInFullScreenBinding(for: activityType))
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                    .disabled(settings.settings.hideLiveActivityInFullScreen)
                    .opacity(settings.settings.hideLiveActivityInFullScreen ? 0.5 : 1.0)

                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.hideLiveActivityInFullScreen)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Persistent Activity").font(.headline).padding([.top, .horizontal])

                    InfoContainer(
                        text: "Choose one activity to be displayed persistently when no other higher-priority activity is active.",
                        iconName: "pin.circle.fill",
                        color: .blue
                    ).padding()

                    HStack {
                        Text("Persistent Activity")
                        Spacer()
                        Picker("Persistent Activity", selection: persistentActivityBinding) {
                            ForEach(PersistentActivitySelection.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding()

                    if currentPersistentActivity == .stats && !settings.settings.statsLiveActivityEnabled {
                        InfoContainer(text: "Enable the 'Stats' live activity below to select it as persistent.", iconName: "info.circle", color: .yellow)
                            .padding([.horizontal, .bottom])
                    } else if currentPersistentActivity == .weather && !settings.settings.weatherLiveActivityEnabled {
                        InfoContainer(text: "Enable the 'Weather' live activity below to select it as persistent.", iconName: "info.circle", color: .yellow)
                            .padding([.horizontal, .bottom])
                    } else if currentPersistentActivity == .battery && !settings.settings.batteryLiveActivityEnabled {
                        InfoContainer(text: "Enable the 'Weather' live activity below to select it as persistent.", iconName: "info.circle", color: .yellow)
                            .padding([.horizontal, .bottom])
                    }

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Weather Live Activity Popup Interval")
                        Spacer()
                        Picker("", selection: $settings.settings.weatherLiveActivityInterval) {
                            Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15); Text("30 min").tag(30)
                        }.labelsHidden()
                    }
                    .padding()
                    .disabled(currentPersistentActivity == .weather)
                    .opacity(currentPersistentActivity == .weather ? 0.5 : 1.0)
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: currentPersistentActivity)

                if settings.settings.statsLiveActivityEnabled {
                    SensorSelectionView(
                        selectedStats: $settings.settings.selectedStats,
                        selectedSensorKeys: $settings.settings.selectedSensorKeys,
                        allSensors: availableSensors
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.settings.statsLiveActivityThresholdEnabled) {
                            Text("Only Show When Usage is High")
                                .font(.headline)
                        }
                        .padding()
                        .toggleStyle(.switch)

                        if settings.settings.statsLiveActivityThresholdEnabled {
                            VStack(alignment: .leading, spacing: 15) {
                                StatThresholdRow(label: "CPU", threshold: binding(for: .cpu))
                                StatThresholdRow(label: "RAM", threshold: binding(for: .ram))
                                StatThresholdRow(label: "GPU", threshold: binding(for: .gpu))
                            }
                            .padding()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding()
                    .modifier(SettingsContainerModifier())
                    .animation(.easeInOut, value: settings.settings.statsLiveActivityThresholdEnabled)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Activity Visibility & Order").font(.headline).padding([.horizontal, .top])
                    Text("Enable, disable, and reorder all available Live Activities.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    if settings.settings.statsLiveActivityEnabled {
                        InfoContainer(text: "Enabling stats will increase the app's cpu and power consumption.", iconName: "info.circle", color: .yellow)
                    }
                    ReorderableVStack(items: $settings.settings.liveActivityOrder) { activity in
                        LiveActivityRowView(
                            activityType: activity,
                            isPremiumLocked: lockedActivityTypes.contains(activity)
                        )
                    }
                    .modifier(SettingsContainerModifier())
                }
                .onChange(of: settings.settings.eyeBreakLiveActivityEnabled) {
                    EyeBreakManager.shared.dismissBreak()
                }

                RequiredPermissionsView(section: .liveActivities)
            }
            .padding(25)
            .animation(.default, value: settings.settings.statsLiveActivityEnabled)
        }
        .onAppear {
            availableSensors = StatsManager.shared.allSensors
        }
        .onDisappear {
            availableSensors = []
        }
    }
}

struct StatThresholdRow: View {
    let label: String
    @Binding var threshold: StatThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $threshold.isEnabled) {
                Text(NSLocalizedString(label, comment: "Settings label"))
            }
            .toggleStyle(.switch)

            if threshold.isEnabled {
                HStack {
                    Text("Threshold")
                        .foregroundColor(.secondary)
                    Spacer()
                    Stepper(
                        "\(threshold.value)%",
                        value: $threshold.value,
                        in: 1...100,
                        step: 5
                    )
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: threshold.isEnabled)
    }
}

fileprivate struct SensorSelectionView: View {
    @Binding var selectedStats: [StatType]
    @Binding var selectedSensorKeys: [String]
    let allSensors: [any Sensor_p]

    private var groupedSensors: [SensorGroup: [any Sensor_p]] {
        Dictionary(grouping: allSensors, by: { $0.group })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Stats Configuration").font(.headline).padding([.top, .horizontal])

            DisclosureGroup("Select high-level stats") {
                VStack(spacing: 0) {
                    ForEach(StatType.allCases) { statType in
                        Toggle(statType.displayName, isOn: Binding<Bool>(
                            get: { selectedStats.contains(statType) },
                            set: { isSelected in
                                if isSelected {
                                    if !selectedStats.contains(statType) {
                                        selectedStats.append(statType)
                                    }
                                } else {
                                    selectedStats.removeAll { $0 == statType }
                                }
                            }
                        ))
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 10)
            }
            .padding()

            Divider().padding(.horizontal)

            DisclosureGroup("Select individual sensors") {
                if allSensors.isEmpty {
                    VStack {
                        ProgressView()
                        Text("Loading sensors...")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(SensorGroup.allCases, id: \.self) { group in
                            if let groupSensors = groupedSensors[group], !groupSensors.isEmpty {
                                Section(header: Text(group.rawValue).font(.headline)) {
                                    ForEach(groupSensors, id: \.key) { sensor in
                                        Toggle(sensor.name, isOn: Binding<Bool>(
                                            get: { selectedSensorKeys.contains(sensor.key) },
                                            set: { isSelected in
                                                if isSelected {
                                                    if !selectedSensorKeys.contains(sensor.key) {
                                                        selectedSensorKeys.append(sensor.key)
                                                    }
                                                } else {
                                                    selectedSensorKeys.removeAll { $0 == sensor.key }
                                                }
                                            }
                                        ))
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(height: 300)
                }
            }
            .padding()
        }
        .modifier(SettingsContainerModifier())
    }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @StateObject private var fetcher = ShortcutsFetcher()
    @State private var searchText: String = ""

    private var filteredAvailableShortcuts: [ShortcutInfo] {
        let selectedIDs = Set(settings.settings.selectedShortcuts.map { $0.id })
        let available = fetcher.allShortcuts.filter { !selectedIDs.contains($0.id) }

        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return available
        }

        return available.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Shortcuts Widget")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Added to Widget")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack {
                        if settings.settings.selectedShortcuts.isEmpty {
                            Text("No shortcuts added.")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                        } else {
                            let rowHeight: CGFloat = 44
                            List {
                                ForEach($settings.settings.selectedShortcuts) { $shortcut in
                                    AddedShortcutRow(shortcut: $shortcut, onRemove: {
                                        removeShortcut(shortcut)
                                    })
                                }
                                .listRowBackground(Color.clear)
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .frame(height: CGFloat(settings.settings.selectedShortcuts.count) * rowHeight)
                        }
                    }
                }
                .padding(.vertical)
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Shortcuts")
                        .font(.headline).padding(.horizontal)

                    TextField("Search Shortcuts", text: $searchText)
                        .textFieldStyle(.plain).padding(8)
                        .background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)

                    if fetcher.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = fetcher.accessError {
                         InfoContainer(text: error, iconName: "exclamationmark.triangle.fill", color: .yellow)
                            .padding(.horizontal)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if filteredAvailableShortcuts.isEmpty {
                                    Text(searchText.isEmpty ? "No shortcuts found." : "No shortcuts match your search.")
                                        .font(.caption).foregroundColor(.secondary).padding()
                                } else {
                                    ForEach(filteredAvailableShortcuts) { shortcut in
                                        AvailableShortcutRow(shortcut: shortcut, onAdd: { addShortcut(shortcut) })
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 350)
                    }
                }
                .padding(.vertical)
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear(perform: fetcher.fetchAllShortcuts)
            .onDisappear {
                fetcher.releaseLoadedShortcuts()
            }
        }
    }

    private func addShortcut(_ shortcut: ShortcutInfo) {
        if !settings.settings.selectedShortcuts.contains(where: { $0.id == shortcut.id }) {
            settings.settings.selectedShortcuts.append(shortcut)
        }
    }

    private func removeShortcut(_ shortcutToRemove: ShortcutInfo) {
        settings.settings.selectedShortcuts.removeAll { $0.id == shortcutToRemove.id }
    }
}

fileprivate struct AddedShortcutRow: View {
    @Binding var shortcut: ShortcutInfo
    let onRemove: () -> Void
    @State private var isShowingEditor = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { isShowingEditor = true }) {
                Image(nsImage: ShortcutsManager.shared.getIcon(for: shortcut))
                    .resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .id(shortcut)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingEditor, arrowEdge: .leading) {
                ShortcutEditorView(shortcut: $shortcut)
            }

            Text(shortcut.name)
            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

fileprivate struct AvailableShortcutRow: View {
    let shortcut: ShortcutInfo
    let onAdd: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                Image(nsImage: ShortcutsManager.shared.getIcon(for: shortcut))
                    .resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(shortcut.name)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isEnabled ? .green.opacity(0.8) : .secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

fileprivate struct ShortcutEditorView: View {
    @Binding var shortcut: ShortcutInfo
    @State private var isShowingIconPicker = false

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { shortcut.backgroundColor?.color ?? .gray },
            set: { shortcut.backgroundColor = CodableColor(color: $0) }
        )
    }

    private var iconColorBinding: Binding<Color> {
        Binding(
            get: { shortcut.iconColor?.color ?? .white },
            set: { shortcut.iconColor = CodableColor(color: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Edit Shortcut")
                .font(.headline)

            Image(nsImage: ShortcutsManager.shared.getIcon(for: shortcut))
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 10) {
                ColorPicker("Background Color", selection: backgroundColorBinding, supportsOpacity: false)
                ColorPicker("Icon Color", selection: iconColorBinding, supportsOpacity: false)

                Button("Change Icon") {
                    isShowingIconPicker = true
                }
            }
        }
        .padding()
        .frame(width: 250)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isShowingIconPicker) {
            IconPickerView { selectedSymbol in
                shortcut.systemImageName = selectedSymbol
            }
        }
    }
}

fileprivate struct IconPickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var isSearchVisible = false

    struct IconSection: Identifiable {
        let id = UUID()
        let title: String
        let symbols: [String]
    }

    static let iconSections: [IconSection] = [
        IconSection(title: "Interface & General", symbols: [
            "house.fill", "house", "gearshape.fill", "gearshape", "gearshape.2.fill", "gearshape.2",
            "slider.horizontal.3", "slider.vertical.3", "ellipsis", "ellipsis.circle.fill", "ellipsis.circle",
            "plus", "plus.circle.fill", "plus.circle", "minus", "minus.circle.fill", "minus.circle",
            "xmark", "xmark.circle.fill", "xmark.circle", "checkmark", "checkmark.circle.fill", "checkmark.circle",
            "questionmark.circle.fill", "questionmark.circle", "info.circle.fill", "info.circle",
            "magnifyingglass", "link", "link.circle.fill", "link.circle", "lock.fill", "lock.open.fill",
            "key.fill", "key", "bell.fill", "bell", "bell.slash.fill", "bell.slash",
            "lightbulb.fill", "lightbulb", "flag.fill", "flag", "bookmark.fill", "bookmark",
            "tag.fill", "tag", "pin.fill", "pin", "archivebox.fill", "archivebox",
            "square.and.arrow.up", "square.and.arrow.down", "arrow.clockwise", "arrow.counterclockwise",
            "gobackward", "goforward", "eject.fill", "eject", "power", "power.circle.fill", "power.circle",
            "app.fill", "app", "window.vertical.closed", "macwindow", "sidebar.left", "sidebar.right",
            "dock.rectangle", "ruler.fill", "ruler", "screwdriver.fill", "screwdriver", "hammer.fill", "hammer",
            "wrench.and.screwdriver.fill", "wrench.and.screwdriver", "eyedropper", "eyedropper.halffull",
            "paintpalette.fill", "paintpalette", "crop", "rotate.right.fill", "rotate.left.fill",
            "sparkle", "sparkles", "star.fill", "star", "heart.fill", "heart",
            "eye.fill", "eye", "eye.slash.fill", "eye.slash", "viewfinder",
            "camera.macro.circle.fill", "camera.macro.circle", "camera.macro",
            "trash.fill", "trash", "square.grid.2x2.fill", "square.grid.2x2", "list.bullet", "list.number",
            "list.dash", "list.clipboard.fill", "list.clipboard"
        ]),

        IconSection(title: "Files & Documents", symbols: [
            "folder.fill", "folder", "folder.circle.fill", "folder.circle", "folder.badge.plus",
            "folder.badge.minus", "folder.badge.person.crop", "folder.badge.questionmark",
            "doc.fill", "doc", "doc.text.fill", "doc.text", "doc.plaintext.fill", "doc.plaintext",
            "doc.richtext.fill", "doc.richtext", "doc.on.doc.fill", "doc.on.doc",
            "doc.on.clipboard.fill", "doc.on.clipboard", "doc.badge.plus", "doc.badge.gearshape.fill",
            "doc.badge.gearshape", "doc.badge.clock.fill", "doc.badge.clock",
            "doc.badge.ellipsis",
            "archivebox.fill", "archivebox", "paperclip", "note.text",
            "note.text.badge.plus", "newspaper.fill", "newspaper", "book.fill", "book", "books.vertical.fill",
            "books.vertical", "scroll.fill", "scroll", "receipt.fill", "receipt",
            "list.bullet.rectangle.portrait.fill", "list.bullet.rectangle.portrait", "text.magnifyingglass",
            "signature", "square.and.pencil", "square.and.pencil.circle.fill", "square.and.pencil.circle",
            "photo.stack.fill", "photo.stack", "square.stack.3d.up.fill", "square.stack.3d.up",
            "square.stack.3d.down.right.fill", "square.stack.3d.down.right",
            "square.stack.3d.up.slash.fill", "square.stack.3d.up.slash",
            "doc.questionmark", "doc.questionmark.fill", "doc.append", "doc.fill.badge.plus",
            "doc.text.image.fill", "doc.text.image", "doc.badge.arrow.up.fill", "doc.badge.arrow.up"
        ]),

        IconSection(title: "Text & Editing", symbols: [
            "pencil", "pencil.circle", "pencil.circle.fill", "eraser.fill", "eraser", "highlighter", "scissors",
            "textformat", "textformat.size", "textformat.abc", "textformat.123",
            "bold", "italic", "underline", "strikethrough", "paragraphsign",
            "text.alignleft", "text.aligncenter", "text.alignright", "text.justify",
            "increase.indent", "decrease.indent", "list.bullet.indent", "quotelevel", "text.bubble.fill",
            "text.bubble", "return", "line.diagonal", "curlybraces",
            "point.topleft.down.curvedto.point.bottomright.up.fill",
            "a.circle.fill", "a.circle", "b.circle.fill", "b.circle", "c.circle.fill", "c.circle",
            "d.circle.fill", "d.circle", "e.circle.fill", "e.circle", "f.circle.fill", "f.circle",
            "g.circle.fill", "g.circle", "h.circle.fill", "h.circle", "i.circle.fill", "i.circle",
            "j.circle.fill", "j.circle", "k.circle.fill", "k.circle", "l.circle.fill", "l.circle",
            "m.circle.fill", "m.circle", "n.circle.fill", "n.circle", "o.circle.fill", "o.circle",
            "p.circle.fill", "p.circle", "q.circle.fill", "q.circle", "r.circle.fill", "r.circle",
            "s.circle.fill", "s.circle", "t.circle.fill", "t.circle", "u.circle.fill", "u.circle",
            "v.circle.fill", "v.circle", "w.circle.fill", "w.circle", "x.circle.fill", "x.circle",
            "y.circle.fill", "y.circle", "z.circle.fill", "z.circle",
            "0.circle.fill", "0.circle", "1.circle.fill", "1.circle", "2.circle.fill", "2.circle",
            "3.circle.fill", "3.circle", "4.circle.fill", "4.circle", "5.circle.fill", "5.circle",
            "6.circle.fill", "6.circle", "7.circle.fill", "7.circle", "8.circle.fill", "8.circle",
            "9.circle.fill", "9.circle",
            "number", "at", "textformat.alt",
            "asterisk", "questionmark", "exclamationmark", "percent",
            "plusminus", "divide", "equal", "dollarsign", "eurosign", "yensign", "coloncurrencysign",
            "bitcoinsign", "point.3.connected.trianglepath.dotted"
        ]),

        IconSection(title: "Media & Audio", symbols: [
            "play.fill", "play", "pause.fill", "pause", "stop.fill", "stop", "record.circle.fill", "record.circle",
            "forward.fill", "forward", "backward.fill", "backward",
            "gobackward.10", "goforward.10", "gobackward.15", "goforward.15", "gobackward.30", "goforward.30",
            "gobackward.45", "goforward.45", "gobackward.60", "goforward.60", "gobackward.75", "goforward.75",
            "gobackward.90", "goforward.90",
            "shuffle", "repeat", "repeat.1", "music.note", "music.note.list", "mic.fill", "mic",
            "mic.slash.fill", "mic.slash", "speaker.wave.3.fill", "speaker.wave.3", "speaker.slash.fill",
            "speaker.slash", "hifispeaker.fill", "hifispeaker", "waveform", "waveform.path", "waveform.path.ecg",
            "waveform.path.ecg.rectangle.fill", "waveform.path.ecg.rectangle", "earpods", "headphones",
            "airpods.chargingcase",
            "airpods", "airpodsmax", "hifispeaker.and.homepodmini.fill",
            "photo.fill", "photo", "camera.fill", "camera", "video.fill", "video", "film.fill", "film",
            "photo.on.rectangle.angled.fill", "photo.on.rectangle.angled",
            "video.badge.plus", "video.badge.waveform.fill", "video.badge.waveform", "airplayvideo", "airplayaudio",
            "captions.bubble.fill", "captions.bubble", "tv.fill", "tv", "tv.and.hifispeaker.fill",
            "opticaldisc.fill", "opticaldisc", "amplifier",
            "metronome.fill", "metronome", "guitars.fill", "guitars", "tuningfork", "square.and.arrow.up.trianglebadge.exclamationmark",
            "music.mic",
            "play.rectangle.fill", "play.rectangle"
        ]),

        IconSection(title: "Time & Date", symbols: [
            "clock.fill", "clock", "alarm.fill", "alarm", "timer", "stopwatch.fill", "stopwatch",
            "calendar", "calendar.circle.fill", "calendar.circle", "calendar.badge.plus",
            "calendar.badge.clock", "hourglass", "hourglass.tophalf.fill", "hourglass.bottomhalf.fill",
            "sunrise.fill", "sunrise", "sunset.fill", "sunset", "moon.stars.fill", "moon.stars",
            "moon.fill", "moon", "timelapse", "rays", "deskclock.fill", "deskclock"
        ]),

        IconSection(title: "Connectivity & Devices", symbols: [
            "wifi", "wifi.slash", "dot.radiowaves.left.and.right", "network", "globe", "globe.americas.fill",
            "globe.europe.africa.fill", "personalhotspot", "antenna.radiowaves.left.and.right",
            "wave.3.right.circle.fill",
            "bolt.fill", "bolt", "bolt.slash.fill", "bolt.slash", "battery.100",
            "battery.25", "battery.0", "battery.100.bolt",
            "bolt.batteryblock.fill", "bolt.batteryblock",
            "iphone", "iphone.landscape", "ipad", "ipad.landscape",
            "applewatch", "applewatch.radiowaves.left.and.right", "applewatch.slash",
            "applewatch.side.right", "macbook", "macbook.gen1", "desktopcomputer",
            "display", "tv.fill", "tv", "keyboard.fill", "keyboard", "magicmouse.fill", "computermouse.fill",
            "computermouse", "printer.fill", "printer", "externaldrive.fill", "externaldrive",
            "externaldrive.fill.badge.plus", "externaldrive.fill.badge.minus",
            "externaldrive.fill.badge.checkmark", "externaldrive.connected.to.line.below",
            "airtag.fill", "airtag", "ipodtouch.landscape", "ipodtouch", "ipod",
            "applepencil", "homepod.fill", "homepod", "homepodmini.fill", "homepodmini", "appletv.fill",
            "airpods.chargingcase.fill", "airpods.chargingcase", "airpods.chargingcase.wireless.fill",
            "airpods.chargingcase.wireless", "bonjour",
            "apple.terminal.fill", "apple.terminal", "laptopcomputer.and.arrow.down",
            "laptopcomputer"
        ]),

        IconSection(title: "Communication", symbols: [
            "envelope.fill", "envelope", "envelope.open.fill", "envelope.open", "tray.fill", "tray",
            "tray.and.arrow.up.fill", "tray.and.arrow.up", "tray.and.arrow.down.fill", "tray.and.arrow.down",
            "paperplane.fill", "paperplane", "message.fill", "message", "bubble.left.fill", "bubble.left",
            "bubble.right.fill", "bubble.right", "bubble.left.and.bubble.right.fill",
            "bubble.left.and.bubble.right", "phone.fill", "phone", "phone.fill.badge.plus", "phone.badge.plus",
            "phone.down.fill", "phone.down.circle.fill",
            "video.fill", "video", "video.badge.plus", "video.badge.waveform.fill", "video.badge.waveform",
            "airplayvideo", "airplayaudio", "mic.circle.fill", "mic.circle",
            "arrowshape.turn.up.left.fill", "arrowshape.turn.up.left",
            "arrowshape.turn.up.left.2.fill", "arrowshape.turn.up.left.2",
            "arrowshape.turn.up.right.fill", "arrowshape.turn.up.right",
            "bell.badge.fill", "bell.badge", "hand.raised.square.fill", "hand.raised.square",
            "phone.arrow.up.right.fill", "phone.arrow.up.right", "phone.arrow.down.left.fill", "phone.arrow.down.left"
        ]),

        IconSection(title: "People & Account", symbols: [
            "person.fill", "person", "person.circle.fill", "person.circle", "person.badge.plus.fill",
            "person.badge.plus", "person.badge.minus.fill", "person.badge.minus",
            "person.crop.circle.fill", "person.crop.circle", "person.crop.circle.badge.plus.fill",
            "person.crop.circle.badge.plus", "person.crop.circle.badge.minus.fill",
            "person.crop.circle.badge.minus", "person.2.fill", "person.2", "person.3.fill", "person.3",
            "figure.walk", "figure.run", "figure.dance", "hand.raised.fill", "hand.raised",
            "hand.thumbsup.fill", "hand.thumbsup", "hand.thumbsdown.fill", "hand.thumbsdown",
            "face.smiling.fill", "face.smiling", "face.dashed.fill", "face.dashed",
            "person.fill.checkmark", "person.crop.circle.badge.checkmark",
            "person.fill.xmark", "person.crop.circle.badge.xmark",
            "person.text.rectangle.fill", "person.text.rectangle", "person.badge.key.fill", "person.badge.key",
            "person.crop.square.fill", "person.crop.square", "person.crop.rectangle.fill", "person.crop.rectangle",
            "figure.seated.side", "figure.stairs", "figure.disc.sports", "figure.baseball", "figure.tennis",
            "figure.basketball", "figure.soccer", "figure.pool.swim", "figure.golf", "figure.climbing",
            "person.and.background.dotted", "person.wave.2.fill", "person.wave.2"
        ]),

        IconSection(title: "Health & Wellness", symbols: [
            "heart.fill", "heart", "heart.circle.fill", "heart.circle", "heart.text.square.fill",
            "staroflife.fill", "staroflife", "cross.case.fill", "cross.case", "pills.fill", "pills",
            "bandage.fill", "bandage", "lungs.fill", "lungs", "brain.head.profile", "brain",
            "waveform.path.ecg.rectangle.fill", "waveform.path.ecg.rectangle", "drop.fill", "drop",
            "thermometer",
            "stethoscope",
            "bed.double.fill", "bed.double", "figure.walk.circle.fill", "figure.walk.circle",
            "figure.strengthtraining.traditional", "figure.yoga", "figure.cooldown",
            "figure.highintensity.intervaltraining", "figure.socialdance",
            "figure.flexibility", "figure.mind.and.body", "figure.cross.training", "figure.barre",
            "figure.stairs", "allergens.fill", "allergens", "thermometer.snowflake",
            "syringe.fill", "syringe", "medical.thermometer.fill", "medical.thermometer"
        ]),

        IconSection(title: "Weather & Environment", symbols: [
            "sun.max.fill", "sun.max", "moon.fill", "moon", "cloud.fill", "cloud", "cloud.sun.fill",
            "cloud.sun", "cloud.rain.fill", "cloud.rain", "cloud.bolt.fill", "cloud.bolt",
            "cloud.bolt.rain.fill", "cloud.bolt.rain", "cloud.snow.fill", "cloud.snow", "cloud.fog.fill",
            "cloud.fog", "tornado", "hurricane", "wind", "wind.circle.fill", "wind.circle",
            "snowflake", "thermometer.sun.fill", "thermometer.sun", "thermometer.snowflake",
            "tree.fill", "tree", "leaf.fill", "leaf", "flame.fill", "flame",
            "drop.fill", "drop", "water.waves",
            "mountain.2.fill", "mountain.2", "sun.haze.fill", "sun.haze", "moon.haze.fill", "moon.haze",
            "smoke.fill", "smoke", "sparkle", "star.leadinghalf.filled"
        ]),

        IconSection(title: "Location & Navigation", symbols: [
            "map.fill", "map", "mappin", "mappin.and.ellipse",
            "location.fill", "location", "location.circle.fill", "location.circle", "location.north.fill",
            "location.north", "location.north.line.fill", "location.north.line", "road.lanes",
            "road.lanes.curved.right", "road.lanes.curved.left", "car.fill", "car", "car.side",
            "bus.fill", "bus", "tram.fill", "tram", "train.side.front.car", "train.side.middle.car",
            "train.side.rear.car", "airplane", "airplane.departure", "airplane.arrival", "bicycle",
            "figure.walk", "ferry.fill", "ferry", "scooter", "truck.box.fill", "truck.box",
            "shippingbox.fill", "shippingbox", "fuelpump.fill", "fuelpump", "bus.doubledecker.fill",
            "bicycle.circle.fill", "bicycle.circle", "figure.walk.circle.fill", "figure.walk.circle",
            "car.front.waves.up.fill", "car.rear.waves.up.fill", "bolt.car.fill", "bus.doubledecker",
            "point.fill.topleft.down.curvedto.point.fill.bottomright.up",
            "compass.drawing", "parkingsign"
        ]),

        IconSection(title: "Sports & Games", symbols: [
            "gamecontroller.fill", "gamecontroller", "dpad.fill", "dpad", "dice.fill", "dice",
            "sportscourt.fill", "sportscourt", "trophy.fill", "trophy", "medal.fill", "medal",
            "figure.tennis", "figure.baseball", "figure.basketball", "figure.soccer", "figure.pool.swim",
            "figure.disc.sports", "figure.golf", "flag.checkered.2.crossed", "target", "scope",
            "circles.hexagongrid.fill", "circles.hexagongrid", "bell.badge.fill", "bell.badge"
        ]),

        IconSection(title: "Accessibility", symbols: [
            "figure.walk.circle.fill", "figure.walk.circle", "figure.roll", "ear.and.waveform", "ear.fill",
            "hand.raised.fingers.spread.fill", "hand.raised.fingers.spread",
            "character.cursor.ibeam",
            "eye.fill", "eye.slash.fill", "mic.fill", "speaker.wave.3.fill", "square.text.square.fill",
            "square.text.square", "waveform.and.magnifyingglass", "questionmark.bubble.fill",
            "accessibility", "accessibility.fill"
        ]),

        IconSection(title: "Shapes & Geometry", symbols: [
            "circle.fill", "circle", "square.fill", "square", "triangle.fill", "triangle",
            "diamond.fill", "diamond", "octagon.fill", "octagon", "hexagon.fill", "hexagon",
            "capsule.fill", "capsule", "oval.fill", "oval", "cube.fill", "cube", "cylinder.fill", "cylinder",
            "cone.fill", "cone", "pyramid.fill", "pyramid", "gearshape.fill", "gearshape",
            "bell.fill", "bell", "lightbulb.fill", "lightbulb", "star.fill", "star", "heart.fill", "heart",
            "bolt.fill", "bolt", "drop.fill", "drop", "water.waves", "sparkle", "sparkles",
            "circle.grid.2x2.fill", "circle.grid.2x2", "rectangle.grid.2x2.fill", "rectangle.grid.2x2",
            "rectangle.grid.3x2.fill", "rectangle.grid.3x2", "square.on.square.dashed",
            "flowchart.fill", "flowchart", "circle.square.fill", "circle.square"
        ])
    ]

    private var filteredIconSections: [IconSection] {
        if searchText.isEmpty {
            return Self.iconSections
        }
        var filteredSections: [IconSection] = []
        let lowercasedSearchText = searchText.lowercased()
        for section in Self.iconSections {
            let matchingSymbols = section.symbols.filter { $0.lowercased().contains(lowercasedSearchText) }
            if !matchingSymbols.isEmpty {
                filteredSections.append(IconSection(title: section.title, symbols: matchingSymbols))
            }
        }
        return filteredSections
    }

    private let columns = [GridItem(.adaptive(minimum: 50))]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Icon")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()

                Button(action: {
                    withAnimation(.spring()) {
                        isSearchVisible.toggle()
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(isSearchVisible ? .accentColor : .white)
                        .padding(5)
                }
                .buttonStyle(.plain)

                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if isSearchVisible {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search icons...", text: $searchText)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                    if filteredIconSections.isEmpty {
                        Text("No icons found for \"\(searchText)\"")
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredIconSections) { section in
                            Text(section.title)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.leading, 5)

                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(section.symbols, id: \.self) { symbolName in
                                    Button(action: {
                                        onSelect(symbolName)
                                        dismiss()
                                    }) {
                                        Image(systemName: symbolName)
                                            .font(.system(size: 24, weight: .bold))
                                            .frame(width: 50, height: 50)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }

        }
        .frame(width: 350, height: 700)
        .background(Color(red: 0.18, green: 0.18, blue: 0.28))
    }
}

struct WeatherInfoSettingsView: View {
    @Binding var selectedInfo: [WeatherInfoType]

    var body: some View {
        SettingsMultiSelectList(
            title: "Visible Weather Info",
            options: WeatherInfoType.selectableCases,
            selection: $selectedInfo,
            label: \.displayName
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct BatteryInfoSettingsView: View {
    @Binding var selectedInfo: [BatteryInfoType]

    var body: some View {
        SettingsMultiSelectList(
            title: "Visible Battery Info",
            options: BatteryInfoType.allCases,
            selection: $selectedInfo,
            label: \.displayName
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct LockScreenSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @State private var notchsettingsHaveChanged: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Lock Screen")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Wallpaper").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Custom Lock Screen Wallpaper",
                        description: "Show your own image or video behind the clock, sign-in controls, and Sapphire widgets on the lock screen.",
                        isOn: $settings.settings.lockScreenCustomWallpaperEnabled
                    )

                    if settings.settings.lockScreenCustomWallpaperEnabled {
                        Divider().padding(.leading, 20)

                        WallpaperFileRow(
                            path: $settings.settings.lockScreenCustomWallpaperPath,
                            panelTitle: "Choose Lock Screen Wallpaper",
                            panelMessage: "Select an image or video to show on your lock screen."
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Use on Desktop",
                            description: "Also show the lock screen wallpaper (live video included) on your desktop, unless a separate desktop wallpaper is set below.",
                            isOn: $settings.settings.lockScreenKeepWallpaperAfterUnlock
                        )
                    }

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Custom Desktop Wallpaper",
                        description: "Use your own image or video on the desktop. A video plays behind your desktop icons and pauses whenever the desktop is covered. The lock screen shows it too unless it has its own wallpaper.",
                        isOn: $settings.settings.desktopWallpaperEnabled
                    )

                    if settings.settings.desktopWallpaperEnabled {
                        Divider().padding(.leading, 20)

                        WallpaperFileRow(
                            path: $settings.settings.desktopWallpaperPath,
                            panelTitle: "Choose Desktop Wallpaper",
                            panelMessage: "Select an image or video to use as your desktop wallpaper."
                        )
                    }

                    if wallpaperConfiguration.desktopPath != nil || wallpaperConfiguration.lockScreenPath != nil {
                        Divider().padding(.leading, 20)

                        HStack {
                            SettingsRowLabel(
                                title: "Scaling",
                                description: "How the wallpaper fits screens with a different shape.",
                                titleFont: .system(size: 14, weight: .medium)
                            )
                            Spacer()
                            Picker("Scaling", selection: $settings.settings.liveWallpaperScaling) {
                                ForEach(WallpaperScaling.allCases) { scaling in
                                    Text(scaling.displayName).tag(scaling)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                        .padding()
                    }

                    if hasVideoWallpaper {
                        Divider().padding(.leading, 20)

                        HStack {
                            SettingsRowLabel(
                                title: "Video Playback",
                                description: settings.settings.liveWallpaperPlaybackMode.description,
                                titleFont: .system(size: 14, weight: .medium)
                            )
                            Spacer()
                            Picker("Video Playback", selection: $settings.settings.liveWallpaperPlaybackMode) {
                                ForEach(LiveWallpaperPlaybackMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 165)
                        }
                        .padding()

                        if settings.settings.liveWallpaperPlaybackMode == .adaptive {
                            Divider().padding(.leading, 20)

                            ToggleRow(
                                title: "Pause in Low Power Mode",
                                description: "Show the first frame instead of playing the video while Low Power Mode is on.",
                                isOn: $settings.settings.liveWallpaperPauseOnLowPower
                            )

                            Divider().padding(.leading, 20)

                            ToggleRow(
                                title: "Pause on Battery Power",
                                description: "Only play video wallpapers while your Mac is plugged in.",
                                isOn: $settings.settings.liveWallpaperPauseOnBattery
                            )
                        }
                    }

                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenCustomWallpaperEnabled)
                .animation(.default, value: settings.settings.desktopWallpaperEnabled)
                .animation(.default, value: hasVideoWallpaper)
                .animation(.default, value: settings.settings.liveWallpaperPlaybackMode)

                ToggleRow(
                    title: "Show Music When Paused",
                    description: "Keep showing the current track in lock screen widgets even when playback is paused.",
                    isOn: $settings.settings.lockScreenShowMusicWhenPaused
                )
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Top Info Widget").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Info Widget(s)",
                        description: "Display small, informational widgets below the clock.",
                        isOn: $settings.settings.lockScreenShowInfoWidget
                    )

                    if settings.settings.lockScreenShowInfoWidget {
                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Hide When Inactive",
                            description: "Only show widgets like Music, Calendar, or Focus when they are active.",
                            isOn: $settings.settings.lockScreenHideInactiveInfoWidgets
                        )

                        Divider().padding(.leading, 20)

                        SettingsMultiSelectList(
                            title: "Visible Widgets",
                            options: LockScreenWidgetType.selectableCases,
                            selection: $settings.settings.lockScreenWidgets,
                            label: \.displayName
                        )

                        if settings.settings.lockScreenWidgets.contains(.weather) {
                            Divider().padding(.horizontal)
                            WeatherInfoSettingsView(selectedInfo: $settings.settings.lockScreenWeatherInfo)
                        }

                        if settings.settings.lockScreenWidgets.contains(.battery) {
                            Divider().padding(.horizontal)
                            BatteryInfoSettingsView(selectedInfo: $settings.settings.lockScreenBatteryInfo)
                        }
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenShowInfoWidget)
                .animation(.default, value: settings.settings.lockScreenWidgets.contains(.weather))
                .animation(.default, value: settings.settings.lockScreenWidgets.contains(.battery))

                VStack(alignment: .leading, spacing: 0) {
                    Text("Main Widget(s)").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Main Widget(s)",
                        description: "Display larger, interactive widgets in the middle of the screen.",
                        isOn: $settings.settings.lockScreenShowMainWidget
                    )

                    if settings.settings.lockScreenShowMainWidget {
                        Divider().padding(.leading, 20)

                        SettingsMultiSelectList(
                            title: "Visible Main Widgets",
                            options: LockScreenMainWidgetType.selectableCases,
                            selection: $settings.settings.lockScreenMainWidgets,
                            label: \.displayName
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenShowMainWidget)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Mini Widgets").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Mini Widget(s)",
                        description: "Display compact widgets below the main widget area.",
                        isOn: $settings.settings.lockScreenShowMiniWidgets
                    )

                    if settings.settings.lockScreenShowMiniWidgets {
                        Divider().padding(.leading, 20)

                        SettingsMultiSelectList(
                            title: "Visible Mini Widgets",
                            options: LockScreenMiniWidgetType.selectableCases,
                            selection: $settings.settings.lockScreenMiniWidgets,
                            label: \.displayName
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenShowMiniWidgets)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Appearance").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Liquid Glass Effect",
                        description: "Apply a shiny, glass-like effect to the lock screen's background.",
                        isOn: $settings.settings.lockScreenLiquidGlassLook
                    )

                    if settings.settings.lockScreenLiquidGlassLook {
                        Divider().padding(.leading, 20)
                        LiquidGlassStylePickerRow(selection: $settings.settings.lockScreenLiquidGlassStyle)

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Frosted Overlay",
                            description: "Layer frosted liquid glass on top of the base glass for a denser, more opaque look.",
                            isOn: $settings.settings.lockScreenFrostedOverLiquidGlass
                        )
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenLiquidGlassLook)
                .animation(.default, value: settings.settings.lockScreenFrostedOverLiquidGlass)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Notch Bar").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Notch on Lock Screen",
                        description: "Keep the Sapphire notch bar visible at the top of the lock screen.",
                        isOn: $settings.settings.lockScreenShowNotch
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Show Lock Screen Live Activity",
                        description: "Display an authentication status activity in the notch on the lock screen.",
                        isOn: $settings.settings.lockScreenLiveActivityEnabled
                    )
                }
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: settings.settings.lockScreenShowNotch) {notchsettingsHaveChanged = true}
        }
    }

    private var wallpaperConfiguration: LiveWallpaperConfiguration {
        LiveWallpaperConfiguration(settings: settings.settings)
    }

    private var hasVideoWallpaper: Bool {
        let configuration = wallpaperConfiguration
        return WallpaperMedia.isVideo(path: configuration.desktopPath)
            || WallpaperMedia.isVideo(path: configuration.lockScreenPath)
    }

}

private struct WallpaperFileRow: View {
    @Binding var path: String?
    let panelTitle: String
    let panelMessage: String

    @State private var thumbnail: CGImage?

    private var media: WallpaperMedia? { WallpaperMedia(path: path) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: media?.isVideo == true ? "film" : "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if media?.isVideo == true, thumbnail != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let media {
                    Text(media.url.lastPathComponent)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(media.isVideo ? "Live video" : "Image")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let path, !path.isEmpty {
                    Text((path as NSString).lastPathComponent)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text("File not found")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("No wallpaper selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Choose…") { choose() }
            if path != nil {
                Button("Remove") { path = nil }
            }
        }
        .padding()
        .task(id: path) {
            thumbnail = nil
            guard let media else { return }
            let image = await Task.detached(priority: .utility) {
                await WallpaperAssetStore.thumbnail(for: media, maxPixelSize: 160)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
    }

    private func choose() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = panelTitle
        panel.message = panelMessage
        panel.prompt = "Choose"
        panel.allowedContentTypes = WallpaperMedia.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        let binding = $path
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            binding.wrappedValue = url.path
        }
    }
}

struct SnapZonesSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var appFetcher = SystemAppFetcher.shared

    @State private var layoutToEdit: SnapLayout?
    @State private var planeToEdit: Plane?
    @State private var isShowingAppPicker = false

    @State private var appToConfigureMultiLayout: String?
    @State private var multiLayoutIDsForSheet: [UUID] = []
    @State private var snapShortcutsExpanded = false

    private var allLayouts: [SnapLayout] {
        LayoutTemplate.allTemplates + settings.settings.customSnapLayouts
    }

    private var viewModeDescription: String {
        switch settings.settings.snapZoneViewMode {
        case .single:
            return "Show one layout at a time, determined by your default or app-specific settings."
        case .multi:
            return "Show a user-defined list of layouts side-by-side in the widget for quick selection."
        }
    }

    private var isShowingMultiLayoutPicker: Binding<Bool> {
        Binding(
            get: { appToConfigureMultiLayout != nil },
            set: { isShowing in
                if !isShowing {
                    appToConfigureMultiLayout = nil
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
                Text("Snap Zones & Planes")
                    .font(.system(size: 32, weight: .bold))
                    .padding(.bottom, 5)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Activate on Drag",
                        description: "Show Snap Zones when dragging near the notch.",
                        isOn: $settings.settings.snapDragEnabled
                    )
                    ToggleRow(
                        title: "Activate on Window Drag",
                        description: "Show Snap Zones when dragging a window. Hold Command to temporarily hide them.",
                        isOn: $settings.settings.snapOnWindowDragEnabled
                    )

                    Divider().padding(.leading, 20)

                    DeferredValueEditor(value: $settings.settings.snapActivationDelay) { draft, onEditingChanged in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Activation Delay")
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(String(format: "%.2fs", draft.wrappedValue))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: draft, in: 0.1...1.0, step: 0.05, onEditingChanged: onEditingChanged)
                            Text("Wait this long in the activation zone before opening Snap Zones. Helps avoid accidental triggers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()

                    Divider().padding(.leading, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reposition & Resize")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Picker("Reposition & Resize", selection: $settings.settings.snapWindowAnimation) {
                                ForEach(SnapWindowAnimation.allCases) { animation in
                                    Text(animation.displayName).tag(animation)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        Text(settings.settings.snapWindowAnimation.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .modifier(SettingsContainerModifier())

                snapShortcutsManagementSection

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Global Widget Style").font(.headline)
                        Spacer()
                        Picker("Widget View Style", selection: $settings.settings.snapZoneViewMode) {
                            ForEach(SnapZoneViewMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }.padding()

                    Text(viewModeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom)

                }.modifier(SettingsContainerModifier())

                if settings.settings.snapZoneViewMode == .single {
                    singleLayoutsManagementSection
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    multiLayoutsManagementSection
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                appSpecificLayoutsSection
                customLayoutsSection
                planesManagementSection
                RequiredPermissionsView(section: .snapZones)
            }
            .padding(25)
            .animation(.easeInOut(duration: 0.2), value: settings.settings.snapZoneViewMode)
        }
        .onAppear(perform: appFetcher.fetchApps)
        .sheet(item: $layoutToEdit) { layout in
            LayoutEditorView(layout: Binding(
                get: { layout },
                set: { updatedLayout in layoutToEdit = updatedLayout }
            ), onSave: saveLayout)
        }
        .sheet(isPresented: isShowingMultiLayoutPicker) {
            if let bundleId = appToConfigureMultiLayout {
                MultiLayoutPickerView(
                    appName: appName(for: bundleId),
                    allLayouts: allLayouts,
                    initialLayoutIDs: multiLayoutIDsForSheet,
                    onSave: { newIDs in
                        modifySettings { $0.appSpecificLayoutConfigurations[bundleId] = .multi(layoutIDs: newIDs) }
                    }
                )
            }
        }
        .sheet(item: $planeToEdit) { plane in
            PlaneEditorView(plane: Binding(
                get: { plane },
                set: { updatedPlane in planeToEdit = updatedPlane }
            ), allLayouts: allLayouts, allApps: appFetcher.apps, onSave: savePlane)
        }
        .popover(isPresented: $isShowingAppPicker, arrowEdge: .bottom) {
            AppPickerView(apps: appFetcher.apps, onSelect: addAppSpecificLayout)
        }
    }

    @ViewBuilder
    private var snapShortcutsManagementSection: some View {
        DisclosureGroup(isExpanded: $snapShortcutsExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                PremiumFeatureView(feature: .snapZonesKeyboardShortcuts) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Assign a shortcut to a zone to snap the currently focused window there. Recording a shortcut already used by another zone moves it to this zone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        ForEach(allLayouts) { layout in
                            SnapZoneShortcutLayoutView(
                                layout: layout,
                                shortcuts: settings.settings.snapZoneShortcuts,
                                onChange: { zoneID, shortcut in
                                    modifySettings { $0.setSnapZoneShortcut(shortcut, for: layout.id, zoneID: zoneID) }
                                }
                            )
                            if layout.id != allLayouts.last?.id {
                                Divider().padding(.leading, 20)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Snap Zone Shortcuts", systemImage: "keyboard")
                .font(.headline)
                .padding([.top, .horizontal])
                .padding(.bottom, 6)
        }
        .modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var singleLayoutsManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Global Default Layout").font(.headline)
                Spacer()
                ModernMenuPicker(selection: $settings.settings.defaultSnapLayout, options: allLayouts, titleKeyPath: \.name)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var multiLayoutsManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Global Multi-View Layouts").font(.headline)
                Spacer()
                Menu {
                    let alreadyAddedIDs = Set(settings.settings.snapZoneLayoutOptions)
                    let availableLayouts = allLayouts.filter { !alreadyAddedIDs.contains($0.id) }

                    if availableLayouts.isEmpty { Text("All layouts added") }
                    else {
                        ForEach(availableLayouts) { layout in
                            Button(layout.name) { addLayoutOption(layout.id) }
                        }
                    }
                } label: {
                    HStack { Image(systemName: "plus"); Text("Add Layout") }
                }
                .buttonStyle(.borderless).tint(.accentColor)
                .disabled(allLayouts.count == settings.settings.snapZoneLayoutOptions.count)

            }.padding([.horizontal, .top]).padding(.bottom, 8)

            Text("Add and reorder the layouts that appear in the Multi-View widget by default.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
            Divider()

            if settings.settings.snapZoneLayoutOptions.isEmpty {
                 Text("Click 'Add Layout' to build your global multi-view widget.")
                     .foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                List {
                    ForEach(settings.settings.snapZoneLayoutOptions.indices, id: \.self) { index in
                        let layoutID = settings.settings.snapZoneLayoutOptions[index]
                        if let layout = allLayouts.first(where: { $0.id == layoutID }) {
                            HStack {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                                Text(layout.name)
                                Spacer()
                                Button {
                                    deleteLayoutOption(at: IndexSet(integer: index))
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onMove(perform: moveLayoutOption)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .frame(height: CGFloat(settings.settings.snapZoneLayoutOptions.count) * 28)
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var appSpecificLayoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("App-Specific Overrides").font(.headline)
                Spacer()
                Button("Add App") { isShowingAppPicker = true }.buttonStyle(.borderless).tint(.accentColor)
            }.padding([.horizontal, .top]).padding(.bottom, 8)
            Text("Force a specific layout mode (Single or Multi) when dragging a particular app.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
            Divider()
            if settings.settings.appSpecificLayoutConfigurations.isEmpty {
                 Text("No app-specific overrides configured.").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ForEach(settings.settings.appSpecificLayoutConfigurations.keys.sorted(), id: \.self) { bundleId in
                    AppSpecificLayoutConfigRow(
                        app: app(for: bundleId),
                        appName: appName(for: bundleId),
                        allLayouts: allLayouts,
                        configuration: bindingForAppConfig(bundleId),
                        onEditMulti: {
                            if case .multi(let layoutIDs) = settings.settings.appSpecificLayoutConfigurations[bundleId] {
                                self.multiLayoutIDsForSheet = layoutIDs
                            } else {
                                self.multiLayoutIDsForSheet = []
                            }
                            self.appToConfigureMultiLayout = bundleId
                        },
                        onDelete: {
                            modifySettings { $0.appSpecificLayoutConfigurations.removeValue(forKey: bundleId) }
                        }
                    )
                    Divider().padding(.leading, 60)
                }
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var customLayoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Custom Layouts").font(.headline)
                Spacer()
                Button("New Layout") { layoutToEdit = SnapLayout(name: "New Custom Layout", zones: []) }.buttonStyle(.borderless).tint(.accentColor)
            }.padding()
            Divider()
            if settings.settings.customSnapLayouts.isEmpty {
                Text("No custom layouts created yet.").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ForEach(settings.settings.customSnapLayouts) { layout in
                    CustomLayoutRow(layout: layout, onEdit: { layoutToEdit = layout }, onDelete: { deleteLayout(layout) })
                    Divider().padding(.leading, 20)
                }
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var planesManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Planes").font(.title2.bold())
                Spacer()
                Button("New Plane") {
                    guard let firstLayout = allLayouts.first else { return }
                    planeToEdit = Plane(name: "New Plane", layoutID: firstLayout.id)
                }.buttonStyle(.borderless).tint(.accentColor)
            }.padding([.horizontal, .top]).padding(.bottom, 8)
            Text("Trigger layouts with keyboard shortcuts to arrange windows instantly.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
            Divider()
            if settings.settings.planes.isEmpty {
                Text("No Planes created yet.").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ForEach($settings.settings.planes) { $plane in
                    PlaneRow(plane: $plane, onEdit: { planeToEdit = $plane.wrappedValue }, onDelete: { deletePlane(withId: $plane.id) })
                    Divider().padding(.leading, 20)
                }
            }
        }.modifier(SettingsContainerModifier())
    }

    // MARK: - Helper Functions
    private func modifySettings(_ modification: (inout Settings) -> Void) {
        var newSettings = settings.settings
        modification(&newSettings)
        settings.settings = newSettings
    }

    private func saveLayout(_ savedLayout: SnapLayout) { modifySettings { settings in if let index = settings.customSnapLayouts.firstIndex(where: { $0.id == savedLayout.id }) { settings.customSnapLayouts[index] = savedLayout } else { settings.customSnapLayouts.append(savedLayout) } } }
    private func savePlane(_ savedPlane: Plane) { modifySettings { settings in if let index = settings.planes.firstIndex(where: { $0.id == savedPlane.id }) { settings.planes[index] = savedPlane } else { settings.planes.append(savedPlane) } } }

    private func deleteLayout(_ layoutToDelete: SnapLayout) {
        modifySettings { settings in
            settings.customSnapLayouts.removeAll { $0.id == layoutToDelete.id }
            if settings.defaultSnapLayout.id == layoutToDelete.id {
                settings.defaultSnapLayout = LayoutTemplate.columns
            }
            for (bundleID, config) in settings.appSpecificLayoutConfigurations {
                switch config {
                case .single(let layoutID) where layoutID == layoutToDelete.id:
                    settings.appSpecificLayoutConfigurations.removeValue(forKey: bundleID)
                case .multi(var layoutIDs):
                    layoutIDs.removeAll { $0 == layoutToDelete.id }
                    settings.appSpecificLayoutConfigurations[bundleID] = .multi(layoutIDs: layoutIDs)
                default:
                    break
                }
            }
            settings.snapZoneShortcuts.removeAll { $0.layoutID == layoutToDelete.id }
            settings.planes.removeAll { $0.layoutID == layoutToDelete.id }
        }
    }

    private func deletePlane(withId planeId: UUID) { modifySettings { settings in settings.planes.removeAll { $0.id == planeId } } }

    private func addAppSpecificLayout(_ appBundleId: String) {
        modifySettings { settings in
            if settings.appSpecificLayoutConfigurations[appBundleId] == nil {
                let firstLayoutID = allLayouts.first?.id ?? LayoutTemplate.columns.id
                settings.appSpecificLayoutConfigurations[appBundleId] = .single(layoutID: firstLayoutID)
            }
        }
        isShowingAppPicker = false
    }

    private func app(for bundleId: String) -> SystemApp? { appFetcher.apps.first { $0.id == bundleId } }
    private func appName(for bundleId: String) -> String { app(for: bundleId)?.name ?? bundleId }

    private func bindingForAppConfig(_ bundleId: String) -> Binding<AppSnapLayoutConfiguration> {
        Binding(
            get: { settings.settings.appSpecificLayoutConfigurations[bundleId] ?? .useGlobalDefault },
            set: { newConfig in modifySettings { $0.appSpecificLayoutConfigurations[bundleId] = newConfig } }
        )
    }

    private func addLayoutOption(_ layoutID: UUID) { modifySettings { $0.snapZoneLayoutOptions.append(layoutID) } }
    private func moveLayoutOption(from source: IndexSet, to destination: Int) { modifySettings { $0.snapZoneLayoutOptions.move(fromOffsets: source, toOffset: destination) } }
    private func deleteLayoutOption(at offsets: IndexSet) { modifySettings { $0.snapZoneLayoutOptions.remove(atOffsets: offsets) } }
}

fileprivate struct SnapZoneShortcutLayoutView: View {
    let layout: SnapLayout
    let shortcuts: [SnapZoneShortcut]
    let onChange: (UUID, KeyboardShortcut?) -> Void

    @ObservedObject private var shortcutRecorder = GlobalShortcutRecorder.shared

    private func shortcut(for zoneID: UUID) -> KeyboardShortcut? {
        shortcuts.first { $0.layoutID == layout.id && $0.zoneID == zoneID }?.shortcut
    }

    private func recordingIdentifier(for zoneID: UUID) -> String {
        "snap-zone-\(layout.id.uuidString)-\(zoneID.uuidString)"
    }

    private func toggleRecording(for zoneID: UUID) {
        let identifier = recordingIdentifier(for: zoneID)
        if shortcutRecorder.isRecording {
            if shortcutRecorder.recordingIdentifier == identifier {
                shortcutRecorder.stopRecording()
            }
            return
        }

        shortcutRecorder.startRecording(identifier: identifier) { key, flags in
            onChange(zoneID, KeyboardShortcut(key: key, modifiers: flags))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(Color.accentColor)
                Text(layout.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(layout.zones.count) zones")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                let zoneShortcut = shortcut(for: zone.id)
                let identifier = recordingIdentifier(for: zone.id)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zone \(index + 1)")
                            .font(.system(size: 13, weight: .medium))
                        Text("\(Int(zone.width * 100))% x \(Int(zone.height * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button(action: { toggleRecording(for: zone.id) }) {
                        HStack(spacing: 6) {
                            if shortcutRecorder.isRecording && shortcutRecorder.recordingIdentifier == identifier {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Recording...")
                            } else if let zoneShortcut {
                                Image(systemName: "keyboard")
                                Text("\(KeyboardShortcutHelper.description(for: zoneShortcut.modifiers))\(zoneShortcut.key)")
                            } else {
                                Image(systemName: "keyboard")
                                Text("Record")
                            }
                        }
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(minWidth: 125)
                    }
                    .buttonStyle(.bordered)
                    .disabled(shortcutRecorder.isRecording && shortcutRecorder.recordingIdentifier != identifier)
                    .help(zoneShortcut == nil ? "Record a shortcut for Zone \(index + 1)" : "Change the shortcut for Zone \(index + 1)")

                    if zoneShortcut != nil {
                        Button {
                            onChange(zone.id, nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear shortcut")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }
}

fileprivate struct AppSpecificLayoutConfigRow: View {
    let app: SystemApp?
    let appName: String
    let allLayouts: [SnapLayout]
    @Binding var configuration: AppSnapLayoutConfiguration
    let onEditMulti: () -> Void
    let onDelete: () -> Void

    private enum ConfigType: Int, Identifiable {
        case useDefault = 0, single, multi
        var id: Int { self.rawValue }
    }

    private var configTypeBinding: Binding<ConfigType> {
        Binding(
            get: {
                switch configuration {
                case .useGlobalDefault: return .single
                case .single: return .single
                case .multi: return .multi
                }
            },
            set: { newType in
                switch newType {
                case .single:
                    if case .single = configuration { return }
                    let firstLayoutID = allLayouts.first?.id ?? LayoutTemplate.columns.id
                    configuration = .single(layoutID: firstLayoutID)
                case .multi:
                    if case .multi = configuration { return }
                    configuration = .multi(layoutIDs: [])
                case .useDefault:
                    break
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            if let app {
                SystemAppIconView(app: app, size: 28, cornerRadius: 6)
            } else {
                Image(systemName: "app.dashed").font(.title2).frame(width: 28)
            }

            Text(appName).lineLimit(1)
            Spacer()

            Picker("Mode", selection: configTypeBinding) {
                Text("Single").tag(ConfigType.single)
                Text("Multi").tag(ConfigType.multi)
            }
            .labelsHidden().frame(width: 180)

            switch configuration {
            case .single(let layoutID):
                let binding = Binding(
                    get: { layoutID },
                    set: { newID in configuration = .single(layoutID: newID) }
                )
                ModernMenuPickerWithID(selection: binding, options: allLayouts, titleKeyPath: \.name)
                    .frame(width: 150)
            case .multi:
                Button("Edit", action: onEditMulti).buttonStyle(.borderless).tint(.accentColor)
            case .useGlobalDefault:
                EmptyView().frame(width: 150, height: 1)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.body).foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain).padding(.leading, 8)
        }
        .padding(.vertical, 8).padding(.horizontal, 20)
    }
}

fileprivate struct MultiLayoutPickerView: View {
    @Environment(\.dismiss) var dismiss
    let appName: String
    let allLayouts: [SnapLayout]
    let onSave: ([UUID]) -> Void

    @State private var editedLayoutIDs: [UUID]

    init(appName: String, allLayouts: [SnapLayout], initialLayoutIDs: [UUID], onSave: @escaping ([UUID]) -> Void) {
        self.appName = appName
        self.allLayouts = allLayouts
        self.onSave = onSave
        self._editedLayoutIDs = State(initialValue: initialLayoutIDs)
    }

    private var availableLayouts: [SnapLayout] {
        allLayouts.filter { !editedLayoutIDs.contains($0.id) }
    }

    private func layout(for id: UUID) -> SnapLayout? {
        allLayouts.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Multi-View for \(appName)").font(.title2.bold()).padding()
            Divider()

            HSplitView {
                VStack(alignment: .leading) {
                    Text("Available Layouts").font(.headline).padding([.top, .horizontal])
                    List(availableLayouts) { layout in
                        Button(action: { editedLayoutIDs.append(layout.id) }) {
                            HStack { Text(layout.name); Spacer(); Image(systemName: "plus.circle.fill").foregroundColor(.green) }
                        }.buttonStyle(.plain)
                    }.listStyle(.sidebar)
                }
                .frame(minWidth: 220)

                VStack(alignment: .leading) {
                    Text("Selected Layouts (Drag to Reorder)").font(.headline).padding([.top, .horizontal])
                    List {
                        ForEach(editedLayoutIDs.indices, id: \.self) { index in
                            if let layout = layout(for: editedLayoutIDs[index]) {
                                HStack {
                                    Text(layout.name)
                                    Spacer()
                                    Button {
                                        delete(at: IndexSet(integer: index))
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onMove(perform: move)
                    }.listStyle(.sidebar)
                }
                .frame(minWidth: 220)
            }

            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(editedLayoutIDs)
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 550, height: 450)
    }

    private func move(from source: IndexSet, to destination: Int) {
        editedLayoutIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func delete(at offsets: IndexSet) {
        editedLayoutIDs.remove(atOffsets: offsets)
    }
}

fileprivate struct ModernMenuPicker<T: Identifiable & Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let titleKeyPath: KeyPath<T, String>

    private var selectedOptionName: String {
        return options.first { $0.id == selection.id }?[keyPath: titleKeyPath] ?? "Select"
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option[keyPath: titleKeyPath]) {
                    selection = option
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedOptionName)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct CustomLayoutRow: View {
    let layout: SnapLayout
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "rectangle.3.group")
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(.accentColor)
            Text(layout.name).font(.headline)
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .tint(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .tint(.red)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

fileprivate struct ModernMenuPickerWithID<T: Identifiable & Hashable>: View where T.ID == UUID {
    @Binding var selection: T.ID
    let options: [T]
    let titleKeyPath: KeyPath<T, String>
    var defaultID: T.ID? = nil
    var defaultTitle: String = "Default"

    private var selectedOptionName: String {
        if let defaultID = defaultID, selection == defaultID {
            return defaultTitle
        }
        return options.first { $0.id == selection }?[keyPath: titleKeyPath] ?? "Select"
    }

    var body: some View {
        Menu {
            if let defaultID = defaultID {
                Button(defaultTitle) { selection = defaultID }
                Divider()
            }
            ForEach(options) { option in
                Button(option[keyPath: titleKeyPath]) { selection = option.id }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedOptionName)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct PlaneRow: View {
    @Binding var plane: Plane
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var shortcutDescription: String {
        guard let shortcut = plane.shortcut else { return "No shortcut set" }
        return "\(KeyboardShortcutHelper.description(for: shortcut.modifiers)) \(shortcut.key)"
    }

    var body: some View {
        HStack {
            Image(systemName: "keyboard")
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(.accentColor)
                .onTapGesture(perform: onEdit)

            VStack(alignment: .leading) {
                Text(plane.name).font(.headline)
                Text(shortcutDescription)
                    .font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

fileprivate struct AppPickerView: View {
    let apps: [SystemApp]
    let onSelect: (String) -> Void
    @State private var searchText = ""

    private var filteredApps: [SystemApp] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Apps", text: $searchText)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.black.opacity(0.1))

            List(filteredApps) { app in
                Button(action: { onSelect(app.id) }) {
                    HStack {
                        SystemAppIconView(app: app, size: 24, cornerRadius: 4)
                        Text(app.name)
                    }
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
        .frame(width: 300, height: 400)
        .background(.ultraThinMaterial)
    }
}

struct NotificationsSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Notifications")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                InfoContainer(text: "All notifications and focus features are in development.", iconName: "info.circle.fill", color: .yellow)

                VStack(spacing: 0) {
                    HStack {
                        Text("Enable Notifications")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        SettingsSwitch(isOn: $settings.settings.masterNotificationsEnabled)
                            .animation(.default, value: settings.settings.masterNotificationsEnabled)
                    }
                    .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 20) {

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Verification Codes")
                            .font(.headline)
                            .padding([.top, .horizontal])

                        ToggleRow(
                            title: "Only show notifications with verification codes",
                            description: "Filter notifications to only display when a code (OTP) is detected.",
                            isOn: $settings.settings.onlyShowVerificationCodeNotifications
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Show copy button for detected codes",
                            description: "Add a quick action to copy the code from supported notifications.",
                            isOn: $settings.settings.showCopyButtonForVerificationCodes
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Auto-copy verification codes",
                            description: "Automatically copy OTP codes to the clipboard when detected.",
                            isOn: $settings.settings.autoCopyVerificationCodes
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "OTP notch popover",
                            description: "Show a dedicated verification-code popover in the notch.",
                            isOn: $settings.settings.otpLiveActivityEnabled
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Scan Mail for OTP codes",
                            description: "Watch Mail.app unread messages for verification codes (no AI).",
                            isOn: $settings.settings.mailOTPDetectionEnabled
                        )
                    }
                    .modifier(SettingsContainerModifier())
                    .disabled(!settings.settings.masterNotificationsEnabled)
                    .opacity(settings.settings.masterNotificationsEnabled ? 1.0 : 0.5)
                    .animation(.easeInOut, value: settings.settings.masterNotificationsEnabled)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Smart Inbox")
                            .font(.headline)
                            .padding([.top, .horizontal])

                        ToggleRow(
                            title: "Enable Smart Inbox",
                            description: "AI-independent Mail features: OTP detection and parcel tracking.",
                            isOn: $settings.settings.smartInboxEnabled
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Parcel tracking from email",
                            description: "Detect UPS/FedEx/USPS/DHL/Amazon tracking numbers in Mail.",
                            isOn: $settings.settings.parcelTrackingEnabled
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Parcel notch popover",
                            description: "Show live package status in the notch when a shipment is active.",
                            isOn: $settings.settings.parcelLiveActivityEnabled
                        )
                    }
                    .modifier(SettingsContainerModifier())

                    VStack(spacing: 0) {
                        ForEach(NotificationSource.allCases) { source in
                            NotificationToggleRowView(source: source)
                            if source != NotificationSource.allCases.last {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 1)
                                    .padding(.leading, 60)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("System Notifications")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            SettingsSwitch(isOn: $settings.settings.systemNotificationsEnabled)
                                .animation(.default, value: settings.settings.systemNotificationsEnabled)
                        }
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))

                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 60)

                        Text("Allow Notifications From:")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .disabled(!settings.settings.systemNotificationsEnabled)
                            .opacity(settings.settings.systemNotificationsEnabled ? 1.0 : 0.5)

                        AppTogglesListView(isEnabled: { app in binding(for: app) }, maxHeight: 360)
                            .disabled(!settings.settings.systemNotificationsEnabled)
                            .opacity(settings.settings.systemNotificationsEnabled ? 1.0 : 0.5)
                    }
                }
                .modifier(SettingsContainerModifier())
                .disabled(!settings.settings.masterNotificationsEnabled)
                .opacity(settings.settings.masterNotificationsEnabled ? 1.0 : 0.5)
                .animation(.easeInOut, value: settings.settings.masterNotificationsEnabled)

                RequiredPermissionsView(section: .notifications)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func binding(for app: SystemApp) -> Binding<Bool> {
        return .init(
            get: { settings.settings.appNotificationStates[app.id, default: true] },
            set: { settings.settings.appNotificationStates[app.id] = $0 }
        )
    }
}

struct ProximityUnlockSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var showPasswordPrompt = false
    @State private var showUnnamedDevices = false
    @State private var isFindingByDistance = false
    @State private var isCalibratingRSSI = false
    @State private var pendingFaceProfileAction: FaceProfileAction?
    @State private var newFaceIDWiFiNetworkName = ""
    @ObservedObject private var wifiMonitor = WiFiStatusMonitor.shared

    private let deviceRowHeight: CGFloat = 38
    private let maxDeviceListHeight: CGFloat = 228

    private struct FaceProfileAction: Identifiable {
        enum Kind {
            case register
            case append
            case delete
        }

        let id = UUID()
        let kind: Kind
        let profileName: String

        var message: String {
            switch kind {
            case .register: return "register the '\(profileName)' face profile"
            case .append: return "add captures to the '\(profileName)' face profile"
            case .delete: return "delete the '\(profileName)' face profile"
            }
        }
    }

    private func performFaceProfileAction(_ action: FaceProfileAction) {
        switch action.kind {
        case .register, .append:
            authManager.beginFaceRegistration(profileName: action.profileName)
        case .delete:
            authManager.deleteFaceProfile(name: action.profileName)
        }
    }

    private var isBluetoothEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { settings.settings.bluetoothUnlockEnabled },
            set: { newValue in
                if newValue {
                    if !authManager.isPasswordSet {
                        showPasswordPrompt = true
                    } else {
                        settings.settings.bluetoothUnlockEnabled = true
                    }
                } else {
                    settings.settings.bluetoothUnlockEnabled = false
                }
            }
        )
    }

    private var isFaceIDEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { settings.settings.faceIDUnlockEnabled },
            set: { newValue in
                if newValue {
                    if !authManager.isPasswordSet {
                        showPasswordPrompt = true
                    } else {
                        settings.settings.faceIDUnlockEnabled = true
                    }
                } else {
                    settings.settings.faceIDUnlockEnabled = false
                }
            }
        )
    }

    private var selectedDevice: Device? {
        guard let selectedIDString = authManager.selectedDeviceID,
              let selectedID = UUID(uuidString: selectedIDString) else { return nil }
        return authManager.scannedDevices.first { $0.id == selectedID } ?? authManager.ble.devices[selectedID]
    }

    private var filteredScannedDevices: [Device] {
        return showUnnamedDevices ? authManager.scannedDevices : authManager.scannedDevices.filter { $0.displayName != "Unnamed Device" }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                InfoContainer(text: "WARNING: All these features are in development and may not work as expected. They might cause unexpected unlocks on your mac. Use at your own risk.", iconName: "exclamationmark.triangle.fill", color: .red)
                if settings.settings.faceIDUnlockEnabled {
                    InfoContainer(text: "Enabling face ID will increase the app's ram usage.", iconName: "info.circle", color: .yellow)
                }
                authenticationSection
                faceIDSection
                bluetoothUnlockSection
                actionsSection
                RequiredPermissionsView(section: .bluetoothUnlock)
            }
            .padding(25)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            PasswordPromptView(
                isPresented: $showPasswordPrompt,
                validate: { authManager.verifyMacLoginPassword($0) }
            ) { password in
                if authManager.verifyAndSavePassword(password) {
                    showPasswordPrompt = false
                }
            }
        }
        .sheet(item: $pendingFaceProfileAction) { action in
            PasswordPromptView(
                isPresented: Binding(
                    get: { pendingFaceProfileAction != nil },
                    set: { if !$0 { pendingFaceProfileAction = nil } }
                ),
                validate: { authManager.verifyPassword($0) },
                title: "Face ID Authentication Required",
                message: "Enter your Mac's password to \(action.message)."
            ) { _ in
                pendingFaceProfileAction = nil
                performFaceProfileAction(action)
            }
        }
        .sheet(item: $authManager.faceRegistrationController, onDismiss: {
            authManager.completeFaceRegistration()
        }) { controller in
            FaceIDRegistrationView(
                cameraController: controller,
                profileName: authManager.profileNameToRegister
            )
        }
        .sheet(isPresented: $isFindingByDistance) {
            FindDeviceByDistanceWizard()
        }
        .sheet(isPresented: $isCalibratingRSSI) {
            CalibrateRSSIView().environmentObject(settings)
        }
        .onAppear {
            authManager.fetchRegisteredFaces()
            authManager.refreshFaceIDLocation()
        }
        .onDisappear {
            if authManager.isScanning {
                authManager.stopScan()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading) {
            Text("Proximity & Face Unlock").font(.largeTitle.bold())
            HStack {
                Button("Lock Screen Now") { authManager.manualLock() }
                    .disabled(!settings.settings.bluetoothUnlockEnabled && !settings.settings.faceIDUnlockEnabled)
                Spacer()
                Text(authManager.status).font(.caption).foregroundColor(.secondary)
            }.padding(.top, 2)
        }
    }

    @ViewBuilder
    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Authentication").font(.headline).padding([.horizontal, .top])
            if authManager.isPasswordSet {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Your Mac's password is securely stored in the Keychain.")
                    Spacer()
                    Button("Change") { showPasswordPrompt = true }
                    Button("Remove", role: .destructive) {
                        authManager.removePassword()
                        var updated = settings.settings
                        updated.bluetoothUnlockEnabled = false
                        updated.faceIDUnlockEnabled = false
                        settings.settings = updated
                    }
                }.padding([.horizontal, .bottom])
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text("To enable Face ID or Bluetooth Unlock, you must first provide your Mac's login password.")
                    Spacer()
                    Button("Set Password") { showPasswordPrompt = true }
                }.padding([.horizontal, .bottom])
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var faceIDSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(title: "Enable Face ID Unlock", description: "Unlock your Mac using facial recognition when you wake the screen.", isOn: isFaceIDEnabled)
                .disabled(!authManager.isPasswordSet)

            if settings.settings.faceIDUnlockEnabled {
                Divider().padding(.leading, 20)

                let registeredFaces = authManager.registeredFaceProfiles
                if registeredFaces.isEmpty {
                    Text("No faces registered. Add a face to begin using Face ID.")
                        .font(.caption).foregroundColor(.secondary).padding()
                } else {
                    ForEach(registeredFaces, id: \.self) { profileName in
                        HStack {
                            Image(systemName: "faceid").font(.title2).foregroundColor(.accentColor)
                            Text(profileName)
                            Spacer()
                            Button("Re-Register") {
                                pendingFaceProfileAction = FaceProfileAction(kind: .register, profileName: profileName)
                            }
                            Button("Delete", role: .destructive) {
                                pendingFaceProfileAction = FaceProfileAction(kind: .delete, profileName: profileName)
                            }
                        }.padding()
                    }
                }

                if registeredFaces.count < 2 {
                    HStack {
                        Spacer()
                        Button(action: {
                            let profileName = registeredFaces.isEmpty ? "Primary Face" : "Secondary Face"
                            pendingFaceProfileAction = FaceProfileAction(kind: .register, profileName: profileName)
                        }) { Label("Add Face", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }.padding(.bottom)
                }

                Divider().padding(.leading, 20)
                faceIDLocationSection
                Divider().padding(.leading, 20)
                faceIDSecuritySection

                Divider().padding(.horizontal)
            }
        }
        .modifier(SettingsContainerModifier())
        .opacity(authManager.isPasswordSet ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var faceIDLocationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Locations").font(.subheadline).bold().padding([.horizontal, .top])

            Picker("Face ID works", selection: $settings.settings.faceIDLocationPolicy) {
                ForEach(FaceIDLocationPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if settings.settings.faceIDLocationPolicy == .selectedWiFiNetworks {
                Text("Use trusted Wi-Fi networks as locations. Face ID will not start on other networks or when the network name is unavailable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 8) {
                    if let currentNetwork = wifiMonitor.state.networkName {
                        Button {
                            addFaceIDWiFiNetwork(currentNetwork)
                        } label: {
                            Label("Use \(currentNetwork)", systemImage: "wifi")
                        }
                        .disabled(settings.settings.faceIDAllowedWiFiNetworks.contains(currentNetwork))
                    } else {
                        Text("No Wi-Fi network detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        authManager.refreshFaceIDLocation()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh current Wi-Fi network")
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    TextField("Wi-Fi network name", text: $newFaceIDWiFiNetworkName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        addFaceIDWiFiNetwork(newFaceIDWiFiNetworkName)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(newFaceIDWiFiNetworkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add Wi-Fi network")
                }
                .padding(.horizontal)

                if settings.settings.faceIDAllowedWiFiNetworks.isEmpty {
                    Text("No trusted locations have been added. Face ID will remain unavailable until one is added.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal)
                } else {
                    ForEach(settings.settings.faceIDAllowedWiFiNetworks, id: \.self) { networkName in
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundStyle(.secondary)
                            Text(networkName)
                            Spacer()
                            Button {
                                settings.settings.faceIDAllowedWiFiNetworks.removeAll { $0 == networkName }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Remove \(networkName)")
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func addFaceIDWiFiNetwork(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !settings.settings.faceIDAllowedWiFiNetworks.contains(trimmedName) else { return }
        settings.settings.faceIDAllowedWiFiNetworks.append(trimmedName)
        newFaceIDWiFiNetworkName = ""
    }

    @ViewBuilder
    private var faceIDSecuritySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Security").font(.subheadline).bold().padding([.horizontal, .top])
            ToggleRow(
                title: "Spoof Detection",
                description: "Block photos, videos, or screen captures from unlocking Face ID.",
                isOn: $settings.settings.faceIDAntiSpoofEnabled
            )
            Divider().padding(.leading, 20)
            CustomSliderRowView(
                label: "Spoof Lock Duration",
                value: $settings.settings.faceIDSpoofLockDuration,
                range: 1...15,
                specifier: "%.0f sec"
            )
            Text("Locks Face ID and requires your password after this much sustained clear spoof detection (not borderline frames).")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 4)
            Divider().padding(.leading, 20)
            CustomSliderRowView(
                label: "No-Match Timeout",
                value: $settings.settings.faceIDMismatchTimeout,
                range: 5...120,
                specifier: "%.0f sec"
            )
            Text("Stops Face ID scanning when your face isn't recognized for this long.")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var bluetoothUnlockSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(
                title: "Enable Bluetooth Unlock",
                description: "Automatically lock and unlock your Mac using a trusted Bluetooth device.",
                isOn: isBluetoothEnabled
            )
            .disabled(!authManager.isPasswordSet)

            Group {
                if settings.settings.bluetoothUnlockEnabled {
                    Divider().padding(.leading, 20)
                    deviceSelectionSection
                    Divider().padding(.horizontal)
                    sensitivitySection
                    Divider().padding(.horizontal)
                    advancedSection
                }
            }.transition(.opacity.combined(with: .move(edge: .top)))
        }
        .modifier(SettingsContainerModifier())
        .opacity(authManager.isPasswordSet ? 1.0 : 0.6)
        .animation(.default, value: settings.settings.bluetoothUnlockEnabled)
    }

    @ViewBuilder
    private var deviceSelectionSection: some View {
        let listHeight = min(maxDeviceListHeight, CGFloat(filteredScannedDevices.count) * deviceRowHeight)
        VStack(alignment: .leading, spacing: 10) {
            Text("Trusted Device").font(.subheadline).bold().padding(.horizontal)
            if let device = selectedDevice {
                DeviceRowView(device: device, isSelected: true) {}.padding(.horizontal)
                HStack {
                    pairingStatusView
                    Spacer()
                    Button("Calibrate Range") { isCalibratingRSSI = true }
                    Button("Forget Device", role: .destructive) { authManager.forgetDevice() }
                }.padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Button(authManager.isScanning ? "Stop Scanning" : "Scan for Devices") {
                            if authManager.isScanning { authManager.stopScan() } else { authManager.startScan(includeUnnamed: showUnnamedDevices) }
                        }
                        if authManager.isScanning { ProgressView().scaleEffect(0.8).padding(.leading) }
                    }
                    Toggle(isOn: $showUnnamedDevices) { Text("Show unnamed devices") }
                        .onChange(of: showUnnamedDevices) { _, newValue in authManager.updateScanFilter(includeUnnamed: newValue) }
                    if showUnnamedDevices && authManager.isScanning {
                        Button("Find by Distance...") { isFindingByDistance = true }.font(.caption).padding(.top, 5).transition(.opacity)
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if authManager.scannedDevices.isEmpty && authManager.isScanning {
                                Text("Scanning...").font(.caption).foregroundColor(.secondary).frame(minHeight: 80)
                            } else if filteredScannedDevices.isEmpty {
                                 Text(showUnnamedDevices ? "No devices found. Ensure device is nearby and discoverable." : "No named devices found. Try enabling 'Show unnamed devices'.")
                                     .font(.caption).foregroundColor(.secondary).frame(minHeight: 80).padding(.horizontal).multilineTextAlignment(.center)
                            } else {
                                ForEach(filteredScannedDevices) { device in
                                    DeviceRowView(device: device) { authManager.selectDevice(uuid: device.id) }
                                    if device.id != filteredScannedDevices.last?.id { Divider().padding(.leading, 50) }
                                }
                            }
                        }
                    }
                    .frame(height: listHeight)
                    .background(Color.black.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .animation(.spring(), value: listHeight)
                }.padding(.horizontal).animation(.default, value: showUnnamedDevices)
            }
        }.padding(.vertical)
    }

    @ViewBuilder
    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sensitivity").font(.subheadline).bold()
                if authManager.selectedDeviceID != nil {
                    Spacer()
                    let rssiString = authManager.lastRSSI.map { "\($0) dBm" } ?? "N/A"
                    Text("Current Signal: \(rssiString)").font(.caption).foregroundColor(.secondary)
                }
            }.padding(.horizontal)
            VStack(spacing: 0) {
                CustomSliderRowView(label: "Unlock RSSI", value: Binding(get: { Double(settings.settings.bluetoothUnlockUnlockRSSI) }, set: { settings.settings.bluetoothUnlockUnlockRSSI = Int($0) }), range: -100...0, specifier: "%.0f dBm")
                Divider().padding(.leading, 20)
                CustomSliderRowView(label: "Lock RSSI", value: Binding(get: { Double(settings.settings.bluetoothUnlockLockRSSI) }, set: { settings.settings.bluetoothUnlockLockRSSI = Int($0) }), range: -100...0, specifier: "%.0f dBm")
            }.padding(.top, 5)
        }.padding(.vertical)
    }

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Advanced").font(.subheadline).bold().padding(.horizontal)
            CustomSliderRowView(label: "Delay to Lock", value: $settings.settings.bluetoothUnlockTimeout, range: 1...60, specifier: "%.0f sec")
            Divider().padding(.leading, 20)
            CustomSliderRowView(label: "No-Signal Timeout", value: $settings.settings.bluetoothUnlockNoSignalTimeout, range: 10...300, specifier: "%.0f sec")
            Divider().padding(.leading, 20)
            ToggleRow(title: "Passive Mode", description: "Uses less energy but may be slightly slower to react.", isOn: $settings.settings.bluetoothUnlockPassiveMode)
            Divider().padding(.leading, 20)
            CustomSliderRowView(label: "Minimum Scan RSSI", value: Binding(get: { Double(settings.settings.bluetoothUnlockMinScanRSSI) }, set: { settings.settings.bluetoothUnlockMinScanRSSI = Int($0) }), range: -100 ... -30, specifier: "%.0f dBm")
        }.padding(.vertical)
    }

    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lock & Unlock Actions").font(.headline).padding([.top, .horizontal])
            ToggleRow(title: "Wake on Proximity", description: "Wake the screen when your device comes into range.", isOn: $settings.settings.bluetoothUnlockWakeOnProximity)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Wake without Unlocking", description: "Only wake the screen, do not enter the password.", isOn: $settings.settings.bluetoothUnlockWakeWithoutUnlocking)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Pause \"Now Playing\" while Locked", description: "Automatically pauses music or videos when the screen locks.", isOn: $settings.settings.bluetoothUnlockPauseMusicOnLock)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Use Screensaver to Lock", description: "Starts the screensaver instead of showing the lock screen.", isOn: $settings.settings.bluetoothUnlockUseScreensaver)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Turn Off Screen on Lock", description: "Puts the display to sleep when locking.", isOn: $settings.settings.bluetoothUnlockTurnOffScreenOnLock)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var pairingStatusView: some View {
        HStack(spacing: 4) {
            switch authManager.monitoredPeripheralState {
            case .connected: Image(systemName: "checkmark.shield.fill").foregroundColor(.green); Text("Paired & Monitoring")
            case .connecting: ProgressView().scaleEffect(0.5); Text("Connecting...")
            case .disconnecting: Image(systemName: "xmark.shield.fill").foregroundColor(.gray); Text("Disconnecting...")
            case .disconnected: Image(systemName: "xmark.shield.fill").foregroundColor(.red); Text("Out of Range")
            @unknown default: Image(systemName: "questionmark.circle.fill").foregroundColor(.gray); Text("Unknown State")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

fileprivate struct DeviceRowView: View {
    let device: Device
    var isSelected: Bool = false
    let action: () -> Void

    private var truncatedUUID: String {
        let fullUUID = device.id.uuidString
        return "\(fullUUID.prefix(8))...\(fullUUID.suffix(4))"
    }

    private func iconForDevice() -> String {
        if let name = device.peripheral?.name, let icon = IconMapper.icon(forName: name) {
            return icon
        }
        return "wave.3.right.circle"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconForDevice())
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.displayName)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(truncatedUUID)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(device.rssi) dBm")
                    .font(.caption.monospaced())
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct FindDeviceByDistanceWizard: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var wizardStep = 1
    @State private var closeReadings: [UUID: Int] = [:]
    @State private var countdown = 30
    @State private var timer: Timer?
    @State private var results: [DetectionResult] = []

    struct DetectionResult: Identifiable {
        let id: UUID
        let device: Device
        let score: Double
        let label: String
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Find Device by Distance").font(.largeTitle.bold())

            switch wizardStep {
            case 1: step1
            case 2: step2
            case 3: step3
            default: Text("An error occurred.")
            }
        }
        .frame(width: 450, height: 400)
        .padding()
        .onAppear { authManager.startScan(includeUnnamed: true) }
        .onDisappear {
            timer?.invalidate()
            authManager.stopScan()
        }
    }

    @ViewBuilder
    private var step1: some View {
        Image(systemName: "arrow.down.to.line.compact").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 1: Bring Device Close").font(.title2)
        Text("Bring your desired device as close as possible to your Mac, then press Next.").multilineTextAlignment(.center).foregroundColor(.secondary)

        let strongestDevice = authManager.scannedDevices.max(by: { $0.rssi < $1.rssi })
        Text("Strongest Signal: \(strongestDevice?.displayName ?? "None") at \(strongestDevice?.rssi ?? -100) dBm")
            .font(.body.bold()).padding()

        Button("Next") {
            self.closeReadings = Dictionary(uniqueKeysWithValues: authManager.scannedDevices.map { ($0.id, $0.rssi) })
            self.wizardStep = 2
            startCountdown()
        }.buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var step2: some View {
        Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 2: Move Device Far Away").font(.title2)
        Text("Now, move the device about 3 meters (10 feet) away. The scan will complete automatically.").multilineTextAlignment(.center).foregroundColor(.secondary)

        Text("Time remaining: \(countdown)s")
            .font(.title3.bold().monospacedDigit()).padding()
        ProgressView(value: Double(30 - countdown), total: 30).frame(width: 200)
    }

    @ViewBuilder
    private var step3: some View {
        Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundColor(.green)
        Text("Step 3: Select Your Device").font(.title2)
        Text("Based on signal change, here are the most likely candidates.").multilineTextAlignment(.center).foregroundColor(.secondary)

        if results.isEmpty {
            Text("No devices showed a significant change in distance.").foregroundColor(.secondary).padding()
        } else {
            List(results) { result in
                Button(action: {
                    authManager.selectDevice(uuid: result.id)
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(result.device.displayName)
                            Text(result.label)
                                .font(.caption)
                                .foregroundColor(labelColor(for: result.label))
                        }
                        Spacer()
                        Text(String(format: "%.0f", result.score))
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }

        Button("Done") { dismiss() }.padding(.top)
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer?.invalidate()
                calculateResults()
                wizardStep = 3
            }
        }
    }

    private func calculateResults() {
        let farReadings = Dictionary(uniqueKeysWithValues: authManager.scannedDevices.map { ($0.id, $0.rssi) })
        var calculatedResults: [DetectionResult] = []

        for (id, closeRSSI) in closeReadings {
            guard let farRSSI = farReadings[id], let device = authManager.scannedDevices.first(where: { $0.id == id }) else { continue }

            let delta = Double(closeRSSI - farRSSI)
            let closeQuality = max(0, min(1, Double(closeRSSI + 85) / 30.0))

            if delta > 5 && closeQuality > 0.2 {
                let score = (delta * 0.7) + (closeQuality * 30 * 0.3)

                let label: String
                if score > 40 { label = "Highly Likely" }
                else if score > 25 { label = "Likely" }
                else { label = "Low Chance" }

                calculatedResults.append(DetectionResult(id: id, device: device, score: score, label: label))
            }
        }

        self.results = calculatedResults.sorted { $0.score > $1.score }
    }

    private func labelColor(for label: String) -> Color {
        switch label {
        case "Highly Likely": return .green
        case "Likely": return .orange
        default: return .secondary
        }
    }
}

fileprivate struct CalibrateRSSIView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var wizardStep = 1
    @State private var countdown = 5
    @State private var timer: Timer?
    @State private var rssiReadings: [Int] = []

    @State private var nearRSSI: Int?
    @State private var farRSSI: Int?

    @State private var isMeasuring = false

    @State private var calibratingDevice: Device?

    private var currentDeviceRSSI: Int? {
        if let device = calibratingDevice,
           let updatedDevice = authManager.scannedDevices.first(where: { $0.id == device.id }) {
            return updatedDevice.rssi
        }
        return calibratingDevice?.rssi
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Calibrate RSSI Range").font(.largeTitle.bold())

            switch wizardStep {
            case 1: step1Near
            case 2: step2Far
            case 3: step3Results
            default: Text("An error occurred.")
            }
        }
        .frame(width: 450, height: 400)
        .padding()
        .onAppear {
            if let selectedIDString = authManager.selectedDeviceID,
               let selectedID = UUID(uuidString: selectedIDString) {
                self.calibratingDevice = authManager.scannedDevices.first { $0.id == selectedID }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    @ViewBuilder
    private var step1Near: some View {
        Image(systemName: "arrow.down.to.line.compact").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 1: Calibrate 'Near' Distance").font(.title2)
        Text("Hold your device where you would normally use it when your Mac is unlocked (e.g., next to the trackpad).").multilineTextAlignment(.center).foregroundColor(.secondary)

        let rssiString = currentDeviceRSSI.map { "\($0) dBm" } ?? "Waiting for signal..."

        if isMeasuring {
            VStack {
                ProgressView("Measuring...", value: Double(5 - countdown), total: 5)
                Text("Current Signal: \(rssiString)")
                    .font(.body.bold().monospacedDigit()).padding()
            }
        } else {
             Text("Current Signal: \(rssiString)")
                .font(.body.bold().monospacedDigit()).padding()
        }

        Button(isMeasuring ? "Measuring..." : "Start Near Calibration") {
            startMeasurement { avgRSSI in
                self.nearRSSI = avgRSSI
                self.wizardStep = 2
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isMeasuring || calibratingDevice == nil)
    }

    @ViewBuilder
    private var step2Far: some View {
        Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 2: Calibrate 'Far' Distance").font(.title2)
        Text("Now, move the device to the distance where you want your Mac to lock automatically.").multilineTextAlignment(.center).foregroundColor(.secondary)

        let rssiString = currentDeviceRSSI.map { "\($0) dBm" } ?? "Waiting for signal..."

        if isMeasuring {
            VStack {
                ProgressView("Measuring...", value: Double(5 - countdown), total: 5)
                Text("Current Signal: \(rssiString)")
                    .font(.body.bold().monospacedDigit()).padding()
            }
        } else {
             Text("Current Signal: \(rssiString)")
                .font(.body.bold().monospacedDigit()).padding()
        }

        Button(isMeasuring ? "Measuring..." : "Start Far Calibration") {
            startMeasurement { avgRSSI in
                self.farRSSI = avgRSSI
                self.wizardStep = 3
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isMeasuring || calibratingDevice == nil)
    }

    @ViewBuilder
    private var step3Results: some View {
        Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundColor(.green)
        Text("Calibration Complete").font(.title2)
        Text("Here are the suggested settings based on your measurements.").multilineTextAlignment(.center).foregroundColor(.secondary)

        if let near = nearRSSI, let far = farRSSI {
            let suggestedUnlock = min(-10, near + 5)
            let suggestedLock = max(-100, far - 5)

            VStack(alignment: .leading, spacing: 15) {
                Text("Measured Average 'Near' Signal: **\(near) dBm**")
                Text("Measured Average 'Far' Signal: **\(far) dBm**")
                Divider()
                Text("Suggested Unlock RSSI: **\(suggestedUnlock) dBm**")
                    .foregroundColor(.green)
                Text("Suggested Lock RSSI: **\(suggestedLock) dBm**")
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            HStack {
                Button("Done") { dismiss() }

                Spacer()

                Button("Apply Settings") {
                    var updated = settings.settings
                    updated.bluetoothUnlockUnlockRSSI = suggestedUnlock
                    updated.bluetoothUnlockLockRSSI = suggestedLock
                    settings.settings = updated
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
            .padding(.top)

        } else {
            Text("Measurement data is missing. Please try again.")
                .foregroundColor(.red)
            Button("Restart") {
                wizardStep = 1
            }
        }
    }

    private func startMeasurement(completion: @escaping (Int) -> Void) {
        isMeasuring = true
        rssiReadings.removeAll()
        countdown = 5

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            if let rssi = currentDeviceRSSI {
                rssiReadings.append(rssi)
            }

            if countdown > 1 {
                countdown -= 1
            } else {
                timer?.invalidate()
                isMeasuring = false

                if !rssiReadings.isEmpty {
                    let average = rssiReadings.reduce(0, +) / rssiReadings.count
                    completion(average)
                } else {
                    completion(currentDeviceRSSI ?? -75)
                }
            }
        }
    }
}

struct FanControlSectionView: View {
    @ObservedObject private var fanManager = FanManager.shared
    @State private var fanToEditID: Int?

    private var isSheetPresented: Binding<Bool> {
        Binding<Bool>(
            get: { self.fanToEditID != nil },
            set: { isShowing in
                if !isShowing {
                    self.fanToEditID = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fan Control").font(.headline).padding([.top, .horizontal])

            InfoContainer(text: "Fan control is in beta. Idle fans at 0 RPM are normal", iconName: "fanblades.fill", color: .orange)
                .padding()

            if fanManager.fans.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No fans detected on this system.")
                        .foregroundColor(.secondary)
                    Text("Fanless Macs (some MacBook Air models) will show this permanently. Otherwise, ensure the Sapphire helper is installed and retry.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry Detection") {
                        Task { await fanManager.refreshHardwareState(forceRediscovery: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                ForEach($fanManager.fans) { $fan in
                    FanRowView(fan: $fan, onCustomize: { fanToEditID = fan.id })
                    if fan.id != fanManager.fans.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
        .modifier(SettingsContainerModifier())
        .sheet(isPresented: isSheetPresented) {
            if let id = fanToEditID, let fanIndex = fanManager.fans.firstIndex(where: { $0.id == id }) {
                FanControlSheetView(fan: $fanManager.fans[fanIndex], availableSensors: fanManager.sensors)
                    .environmentObject(fanManager)
            }
        }
        .environmentObject(fanManager)
        .onAppear { fanManager.beginPolling() }
        .onDisappear { fanManager.endPolling() }
    }
}

struct FanRowView: View {
    @Binding var fan: FanInfo
    let onCustomize: () -> Void
    @EnvironmentObject var fanManager: FanManager

    private var modeString: String {
        switch fanManager.fanModes[fan.id] {
        case .auto: return "Auto"
        case .constant(let rpm): return "Constant \(rpm) RPM"
        case .sensor(let key, _, _):
            return "Sensor: \(SensorNameMap.name(for: key))"
        case .customCurve(let key, let points):
            return "Curve (\(points.count) pts): \(SensorNameMap.name(for: key))"
        case nil: return "Auto"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fan.name.contains("Fan") ? "Fan \(fan.id + 1)" : fan.name)
                    .font(.headline)

                Text("Min: \(fan.minRPM) | Current: \(fan.currentRPM) | Max: \(fan.maxRPM) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Text(modeString)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            Spacer()
            Button("Custom...") { onCustomize() }
        }
        .padding()
    }
}

struct FanControlSheetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var fanManager: FanManager
    @Binding var fan: FanInfo
    let availableSensors: [TemperatureSensor]

    @State private var selectedMode: Int
    @State private var constantRPM: Double
    @State private var sensorKey: String
    @State private var minTemp: Double
    @State private var maxTemp: Double
    @State private var curvePoints: [FanCurvePoint]

    init(fan: Binding<FanInfo>, availableSensors: [TemperatureSensor]) {
        self._fan = fan
        self.availableSensors = availableSensors

        let initialMode = FanManager.shared.fanModes[fan.wrappedValue.id] ?? .auto

        switch initialMode {
        case .auto:
            _selectedMode = State(initialValue: 0)
            _constantRPM = State(initialValue: Double(fan.wrappedValue.minRPM))
            _sensorKey = State(initialValue: availableSensors.first?.key ?? "")
            _minTemp = State(initialValue: 40)
            _maxTemp = State(initialValue: 75)
            _curvePoints = State(initialValue: FanManager.defaultCurvePoints(for: fan.wrappedValue))
        case .constant(let rpm):
            _selectedMode = State(initialValue: 1)
            _constantRPM = State(initialValue: Double(rpm))
            _sensorKey = State(initialValue: availableSensors.first?.key ?? "")
            _minTemp = State(initialValue: 40)
            _maxTemp = State(initialValue: 75)
            _curvePoints = State(initialValue: FanManager.defaultCurvePoints(for: fan.wrappedValue))
        case .sensor(let key, let minT, let maxT):
            _selectedMode = State(initialValue: 2)
            _constantRPM = State(initialValue: Double(fan.wrappedValue.minRPM))
            _sensorKey = State(initialValue: key)
            _minTemp = State(initialValue: Double(minT))
            _maxTemp = State(initialValue: Double(maxT))
            _curvePoints = State(initialValue: FanManager.defaultCurvePoints(for: fan.wrappedValue))
        case .customCurve(let key, let points):
            _selectedMode = State(initialValue: 3)
            _constantRPM = State(initialValue: Double(fan.wrappedValue.minRPM))
            _sensorKey = State(initialValue: key)
            _minTemp = State(initialValue: 40)
            _maxTemp = State(initialValue: 75)
            _curvePoints = State(initialValue: points.isEmpty ? FanManager.defaultCurvePoints(for: fan.wrappedValue) : points)
        }
    }

    private var selectedSensorValueString: String {
        if let sensor = availableSensors.first(where: { $0.key == sensorKey }) {
            return String(format: "%.1f°C", sensor.value)
        }
        return "N/A"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Change Fan Control for '\(fan.name.contains("Fan") ? "Fan \(fan.id + 1)" : fan.name)'")
                .font(.title2.bold())

            Picker("Control Mode", selection: $selectedMode) {
                Text("Automatic").tag(0)
                Text("Constant RPM").tag(1)
                Text("Sensor-based").tag(2)
                Text("Custom Curve").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.bottom)

            if selectedMode == 1 {
                VStack {
                    CustomSliderRowView(label: "Fan Speed", value: $constantRPM, range: Double(fan.minRPM)...Double(fan.maxRPM), specifier: "%.0f RPM")
                }
            } else if selectedMode == 2 {
                sensorPickerSection
                CustomSliderRowView(label: "Start increasing from:", value: $minTemp, range: 20...100, specifier: "%.0f °C")
                    .onChange(of: minTemp) {
                        if minTemp > maxTemp { maxTemp = minTemp }
                    }
                CustomSliderRowView(label: "Maximum temperature:", value: $maxTemp, range: 20...100, specifier: "%.0f °C")
                    .onChange(of: maxTemp) {
                        if maxTemp < minTemp { minTemp = maxTemp }
                    }
            } else if selectedMode == 3 {
                sensorPickerSection
                FanCurveEditorView(fan: fan, points: $curvePoints)
            } else {
                Text("The fan will be controlled automatically by macOS.")
                    .foregroundColor(.secondary)
                    .frame(minHeight: 150, alignment: .center)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("OK") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 580)
        .frame(minHeight: selectedMode == 3 ? 520 : 350)
    }

    @ViewBuilder
    private var sensorPickerSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Based on Sensor:")
                Spacer()
                Picker("Sensor", selection: $sensorKey) {
                    ForEach(availableSensors) { sensor in
                        HStack {
                            Text(sensor.name)
                            Spacer()
                            Text(String(format: "%.1f°C", sensor.value))
                                .foregroundColor(.secondary)
                        }.tag(sensor.key)
                    }
                }
                Text(selectedSensorValueString)
                    .font(.body.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    private func saveAndDismiss() {
        let newMode: FanControlMode
        switch selectedMode {
        case 1:
            newMode = .constant(rpm: Int(constantRPM))
        case 2:
            newMode = .sensor(sensorKey: sensorKey, minTemp: Int(minTemp), maxTemp: Int(maxTemp))
        case 3:
            let sortedPoints = curvePoints.sorted { $0.temperature < $1.temperature }
            newMode = .customCurve(sensorKey: sensorKey, points: sortedPoints)
        default:
            newMode = .auto
        }
        fanManager.setFanMode(for: fan.id, to: newMode)
        dismiss()
    }
}

private struct FanCurveEditorView: View {
    let fan: FanInfo
    @Binding var points: [FanCurvePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Fan Curve").font(.headline)
                Spacer()
                Button("Reset") {
                    points = FanManager.defaultCurvePoints(for: fan)
                }
                .buttonStyle(.borderless)
            }

            Text("Set RPM at each temperature. Sapphire interpolates between points.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                VStack(spacing: 8) {
                    CustomSliderRowView(
                        label: "Point \(index + 1) Temperature",
                        value: Binding(
                            get: { Double(points[index].temperature) },
                            set: { points[index].temperature = Int($0) }
                        ),
                        range: 20...100,
                        specifier: "%.0f °C"
                    )
                    CustomSliderRowView(
                        label: "Point \(index + 1) RPM",
                        value: Binding(
                            get: { Double(points[index].rpm) },
                            set: { points[index].rpm = Int($0) }
                        ),
                        range: Double(fan.minRPM)...Double(fan.maxRPM),
                        specifier: "%.0f RPM"
                    )
                    if points.count > 2 {
                        Button("Remove Point", role: .destructive) {
                            points.remove(at: index)
                        }
                        .font(.caption)
                    }
                }
                if index < points.count - 1 {
                    Divider()
                }
            }

            if points.count < 6 {
                Button {
                    let lastTemp = points.last?.temperature ?? 60
                    let lastRPM = points.last?.rpm ?? fan.minRPM
                    points.append(FanCurvePoint(temperature: min(lastTemp + 10, 95), rpm: min(lastRPM + 500, fan.maxRPM)))
                } label: {
                    Label("Add Point", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct CalibrationView: View {
    @StateObject private var calibrationManager = CalibrationManager.shared
    @StateObject private var batteryMonitor = BatteryMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Battery Calibration").font(.headline).padding([.top, .horizontal])
            InfoContainer(
                text: "Calibrating your battery helps macOS get a more accurate reading of its health and time remaining. This process can take several hours and involves a full charge and discharge cycle. Sleeping will be disabled during calibration.",
                iconName: "gauge.high",
                color: .purple
            ).padding()

            VStack(spacing: 15) {
                if calibrationManager.isActive {
                    VStack(spacing: 8) {
                        Text(calibrationManager.state.description)
                            .font(.headline)
                            .foregroundColor(.secondary)

                        ProgressView(value: calibrationManager.progress)
                            .progressViewStyle(.linear)

                        Text(String(format: "%.1f%% complete", calibrationManager.progress * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Cancel Calibration", role: .destructive) {
                            calibrationManager.cancel()
                        }
                        .padding(.top, 5)
                    }

                } else {
                    VStack(spacing: 12) {
                        if calibrationManager.state == .done {
                             Text("Calibration completed successfully.")
                                .foregroundColor(.green)
                        } else if case .error(let message) = calibrationManager.state {
                            Text(message)
                                .foregroundColor(.red)
                        }

                        Text("Ensure your Mac is plugged in before starting. Do not unplug or put your Mac to sleep during the process.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: {
                            calibrationManager.start()
                        }) {
                            Text("Start Calibration")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(batteryMonitor.currentState?.isPluggedIn == false)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .modifier(SettingsContainerModifier())
    }
}

struct LidAngleCaffeineSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var lidAngleSensor = LidAngleSensor.shared

    private var caffeineTriggerAngleBinding: Binding<Double> {
        $settings.settings.caffeinateLidAngleTrigger
    }

    private var currentAngleText: String {
        guard lidAngleSensor.isAvailable else { return "Unavailable" }
        return "\(Int(lidAngleSensor.angle.rounded()))°"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(
                title: "Black out display using lid angle",
                description: "While caffeinated, set brightness to zero when the lid reaches the trigger angle. This does not put the display to sleep.",
                isOn: $settings.settings.caffeinateTurnOffScreenUsingLidAngle
            )

            Divider().padding(.leading, 20)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Lid Angle")
                    Text(lidAngleSensor.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(currentAngleText)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(lidAngleSensor.isAvailable ? .primary : .secondary)
            }
            .padding()

            if settings.settings.caffeinateTurnOffScreenUsingLidAngle {
                Divider().padding(.leading, 20)
                CustomSliderRowView(
                    label: "Trigger Angle",
                    value: caffeineTriggerAngleBinding,
                    range: 0...140,
                    specifier: "%.0f°"
                )
            }

            Divider().padding(.leading, 20)
            ToggleRow(
                title: "Pause media when nearly closed",
                description: "Automatically pause now playing media and resume when the lid opens back up.",
                isOn: $settings.settings.lidAnglePauseMediaEnabled
            )

            if settings.settings.lidAnglePauseMediaEnabled {
                Divider().padding(.leading, 20)
                CustomSliderRowView(
                    label: "Pause Media Trigger",
                    value: $settings.settings.lidAnglePauseMediaTrigger,
                    range: 0...140,
                    specifier: "%.0f°"
                )
            }

            Divider().padding(.leading, 20)
            ToggleRow(
                title: "Mute system audio when nearly closed",
                description: "Mute all system output as the lid closes, then unmute when it opens past the threshold.",
                isOn: $settings.settings.lidAngleMuteAudioEnabled
            )

            if settings.settings.lidAngleMuteAudioEnabled {
                Divider().padding(.leading, 20)
                CustomSliderRowView(
                    label: "Mute Audio Trigger",
                    value: $settings.settings.lidAngleMuteAudioTrigger,
                    range: 0...140,
                    specifier: "%.0f°"
                )
            }

            Divider().padding(.leading, 20)
            ToggleRow(
                title: "Sleep display when nearly closed",
                description: "Put the display into real macOS display sleep when the lid drops below the chosen angle, then wake it again when reopened. This will attempt to keep caffinate activated while the display is sleeping.",
                isOn: $settings.settings.lidAngleSleepDisplayEnabled
            )

            if settings.settings.lidAngleSleepDisplayEnabled {
                Divider().padding(.leading, 20)
                CustomSliderRowView(
                    label: "Display Sleep Trigger",
                    value: $settings.settings.lidAngleSleepDisplayTrigger,
                    range: 0...140,
                    specifier: "%.0f°"
                )
            }

            Divider().padding(.leading, 20)
            ToggleRow(
                title: "Enable Low Power Mode as lid closes",
                description: "Force Low Power Mode while the lid is partially closed and restore the previous state when reopened.",
                isOn: $settings.settings.lidAngleLowPowerModeEnabled
            )

            if settings.settings.lidAngleLowPowerModeEnabled {
                Divider().padding(.leading, 20)
                CustomSliderRowView(
                    label: "Low Power Trigger",
                    value: $settings.settings.lidAngleLowPowerModeTrigger,
                    range: 0...140,
                    specifier: "%.0f°"
                )
            }

        }
        .modifier(SettingsContainerModifier())
        .onAppear {
            lidAngleSensor.acquire(.caffeineSettingsPreview)
        }
        .onDisappear {
            lidAngleSensor.release(.caffeineSettingsPreview)
        }
    }

}

struct BatterySettingsView: View {
    @State private var selectedTab: String = "Statistics"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                Text("Battery").font(.largeTitle.bold()).padding(.bottom, 10)
                ModernSegmentedPicker(
                    selection: $selectedTab,
                    options: ["Statistics", "Configuration"]
                )
                .padding(.bottom, 5)

            }
            .padding(.horizontal, 25).padding(.top, 25)

            Spacer()

            if selectedTab == "Statistics" {
                ModernBatteryStatsView()
            } else {
                BatteryConfigurationView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .sapphireSettingsWillClose)) { _ in
            selectedTab = "Configuration"
        }
    }
}

struct DateRangePickerView: View {
    @Binding var selection: TimeRange

    @State private var showCustomPicker = false

    @State private var customStartDate: Date
    @State private var customEndDate: Date

    @Namespace private var datePickerNamespace

    init(selection: Binding<TimeRange>) {
        self._selection = selection

        if case .custom(let start, let end) = selection.wrappedValue {
            _customStartDate = State(initialValue: start)
            _customEndDate = State(initialValue: end)
        } else {
            _customStartDate = State(initialValue: Date())
            _customEndDate = State(initialValue: Date())
        }
    }

    private var isCustomSelected: Bool {
        if case .custom = selection {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {

            PickerButton(label: "24h", isSelected: selection == .last24Hours, namespace: datePickerNamespace) {
                updateSelection(.last24Hours)
            }
            PickerButton(label: "7d", isSelected: selection == .last7Days, namespace: datePickerNamespace) {
                updateSelection(.last7Days)
            }
            PickerButton(label: "Month", isSelected: selection == .lastMonth, namespace: datePickerNamespace) {
                updateSelection(.lastMonth)
            }
            PickerButton(label: "Year", isSelected: selection == .lastYear, namespace: datePickerNamespace) {
                updateSelection(.lastYear)
            }

            PickerButton(label: "Custom", isSelected: isCustomSelected, namespace: datePickerNamespace) {
                showCustomPicker = true
            }
            .popover(isPresented: $showCustomPicker, attachmentAnchor: .point(.bottom)) {
                customDatePickerView
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func updateSelection(_ newSelection: TimeRange) {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.7)) {
            selection = newSelection
        }
    }

    private var customDatePickerView: some View {
        VStack(spacing: 15) {
            Text("Select Custom Range")
                .font(.headline)

            DatePicker("Start Date", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date)
            DatePicker("End Date", selection: $customEndDate, in: ...Date(), displayedComponents: .date)

            Button("Apply") {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.7)) {
                    selection = .custom(customStartDate, customEndDate)
                }
                showCustomPicker = false
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(minWidth: 250)
    }
}

fileprivate struct PickerButton: View {
    let label: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Text(NSLocalizedString(label, comment: "Settings label"))
            .font(.subheadline.weight(.bold))
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "datePickerPill", in: namespace)
                    }
                }
            )
            .foregroundColor(isSelected ? .primary : .secondary)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

struct HeroMetricsView: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    private var statusColor: Color {
        if viewModel.isCharging { return MaterialChartPalette.tertiary }
        if viewModel.batteryLevel < 20 { return MaterialChartPalette.error }
        if viewModel.batteryLevel < 50 { return MaterialChartPalette.warning }
        return MaterialChartPalette.primary
    }

    private var metricColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var chargingStatusValue: String {
        if viewModel.isCharging {
            let watts = abs(viewModel.powerConsumption)
            return watts > 0 ? String(format: "%.1f W", watts) : "Active"
        }
        return viewModel.timeRemaining
    }

    private var batteryLevelLabel: Text {
        Text("\(viewModel.batteryLevel)")
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .foregroundStyle(statusColor)
        + Text("%")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(statusColor.opacity(0.7))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Battery")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                batteryLevelLabel
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                MaterialStatChip(
                    label: viewModel.isCharging ? "Charging" : "On Battery",
                    value: chargingStatusValue,
                    color: statusColor,
                    icon: viewModel.isCharging ? "bolt.fill" : "battery.100"
                )
            }
            .fixedSize(horizontal: true, vertical: false)

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                MaterialStatChip(label: "Time Remaining", value: viewModel.timeRemaining, color: MaterialChartPalette.primary, icon: "clock.fill")
                MaterialStatChip(label: "Health", value: "\(viewModel.maxCapacityPercentage)%", color: Color.pink, icon: "heart.fill")
                MaterialStatChip(label: "Cycles", value: "\(viewModel.cycleCount)", color: MaterialChartPalette.secondary, icon: "arrow.triangle.2.circlepath")
                MaterialStatChip(label: "Temperature", value: String(format: "%.1f°C", viewModel.temperature), color: MaterialChartPalette.error, icon: "thermometer.medium")
                MaterialStatChip(label: "Power", value: String(format: "%.1f W", abs(viewModel.powerConsumption)), color: MaterialChartPalette.warning, icon: "bolt.fill")
                MaterialStatChip(label: "Voltage", value: String(format: "%.2f V", viewModel.voltage / 1000.0), color: MaterialChartPalette.tertiary, icon: "wave.3.right")
                MaterialStatChip(label: String(localized: "battery.current"), value: String(format: "%.2f A", Double(abs(viewModel.amperage)) / 1000.0), color: MaterialChartPalette.primary, icon: "arrow.left.arrow.right")
                MaterialStatChip(label: "Condition", value: viewModel.health, color: .pink, icon: "heart.text.square")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .materialChartCard(accent: statusColor)
    }
}

struct SpecRow: View {
    let label: String, value: String, percentage: String?
    init(label: String, value: String, percentage: String? = nil) {
        self.label = label; self.value = value; self.percentage = percentage
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(NSLocalizedString(label, comment: "Settings label"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, alignment: .trailing)
            Text(percentage ?? "")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(percentage == nil ? .clear : .primary)
                .frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 12, design: .rounded))
    }
}

struct ComponentPowerBreakdownView: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject private var statsManager = StatsManager.shared

    private static func finite(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return max(0, v)
    }

    private var systemLoad: Double { Self.finite(statsManager.currentStats?.systemPower ?? viewModel.powerConsumption) }
    private var batteryPower: Double { Self.finite(statsManager.currentStats?.batteryPower ?? viewModel.powerConsumption) }
    private var chargingPower: Double { (viewModel.isCharging && batteryPower < 0) ? abs(batteryPower) : 0 }
    private var adapterPower: Double { Self.finite(statsManager.currentStats?.sensors?.sensors.first { ["PDTR"].contains($0.key) }?.value ?? 0) }
    private var cpuPower: Double { Self.finite(statsManager.currentStats?.sensors?.sensors.first { ["PCPC", "PCTR", "PC0C"].contains($0.key) }?.value ?? 0) }
    private var gpuPower: Double { Self.finite(statsManager.currentStats?.sensors?.sensors.first { ["PGTR", "PG0C", "PCGC"].contains($0.key) }?.value ?? 0) }
    private var displayPower: Double { max(0, systemLoad - (cpuPower + gpuPower)) * 0.4 }
    private var otherPower: Double { max(0, systemLoad - (cpuPower + gpuPower + displayPower)) }
    private var isCharging: Bool { viewModel.isCharging }
    private var adapterConnected: Bool { (viewModel.powerAdapterInfo?.maxPower ?? 0) > 0 }

    private var heroWatts: Double { adapterConnected ? max(adapterPower, systemLoad) : systemLoad }

    private var statusLabel: String {
        if isCharging { return "Charging" }
        if adapterConnected { return "On AC Power" }
        return "On Battery"
    }

    private var statusColor: Color {
        if isCharging { return MaterialChartPalette.tertiary }
        if adapterConnected { return MaterialChartPalette.primary }
        return MaterialChartPalette.warning
    }

    private var components: [(id: String, icon: String, title: String, power: Double, color: Color)] {
        var rows: [(id: String, icon: String, title: String, power: Double, color: Color)] = []
        if isCharging && chargingPower > 0.15 {
            rows.append(("charging", "battery.100.bolt", "Charging", chargingPower, MaterialChartPalette.tertiary))
        }
        if cpuPower > 0.35 {
            rows.append(("cpu", "cpu", "CPU", cpuPower, Color.cyan))
        }
        if gpuPower > 0.35 {
            rows.append(("gpu", "cube.fill", "GPU", gpuPower, MaterialChartPalette.secondary))
        }
        if displayPower > 0.35 {
            rows.append(("display", "display", "Display", displayPower, MaterialChartPalette.warning))
        }
        if otherPower > 0.35 {
            rows.append(("other", "ellipsis.circle", "Other", otherPower, MaterialChartPalette.onSurfaceVariant))
        }
        return rows
    }

    private var totalComponentPower: Double {
        max(components.reduce(0) { $0 + $1.power }, 0.001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            powerHeroHeader
            if !components.isEmpty {
                shareStrip
                componentRows
            } else {
                Text("Waiting for power sensors…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .materialChartCard(accent: statusColor)
        .onAppear {
            statsManager.setPolling(for: "ComponentBreakdown", requiredStats: [.systemPower, .batteryPower, .cpu, .gpu])
        }
        .onDisappear {
            statsManager.setPolling(for: "ComponentBreakdown", requiredStats: [])
        }
    }

    private var powerHeroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("System Power")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", heroWatts))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("W")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .padding(.bottom, 4)
                Spacer(minLength: 0)
                Image(systemName: adapterConnected ? "powerplug.fill" : "battery.100")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(statusColor.opacity(0.85))
            }

            Capsule()
                .fill(statusColor)
                .frame(height: 3)
                .frame(maxWidth: 120, alignment: .leading)

            if adapterConnected || isCharging {
                HStack(spacing: 12) {
                    if adapterConnected {
                        metaChip(icon: "bolt.horizontal.fill", text: String(format: "Adapter %.0f W", adapterPower > 0 ? adapterPower : heroWatts))
                    }
                    metaChip(icon: "laptopcomputer", text: String(format: "Draw %.2f W", systemLoad))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var shareStrip: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(components, id: \.id) { row in
                    Capsule()
                        .fill(row.color)
                        .frame(width: max(4, geo.size.width * CGFloat(row.power / totalComponentPower)))
                }
            }
        }
        .frame(height: 6)
    }

    private var componentRows: some View {
        VStack(spacing: 12) {
            ForEach(components, id: \.id) { row in
                PowerShareRow(
                    icon: row.icon,
                    title: row.title,
                    power: row.power,
                    fraction: row.power / totalComponentPower,
                    color: row.color
                )
            }
        }
    }
}

struct PowerShareRow: View {
    let icon: String
    let title: String
    let power: Double
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(NSLocalizedString(title, comment: "Settings title"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.2f W", power))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .frame(width: 36, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MaterialChartPalette.outline.opacity(0.55))
                        .frame(height: 3)
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, geo.size.width * CGFloat(fraction)), height: 3)
                }
            }
            .frame(height: 3)
        }
    }
}

struct ModernBatteryStatsView: View {
    @StateObject private var viewModel = BatteryStatsViewModel()
    @StateObject private var historyViewModel = BatteryHistoryViewModel()
    @StateObject private var energyViewModel = EnergyViewModel()
    @StateObject private var helperManager = HelperManager.shared
    @ObservedObject private var debugMode = DebugMode.shared
    @State private var selectedTimeRange: TimeRange = .last24Hours

    private let mainGridLayout = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                if debugMode.isEnabled {
                    BatteryDebugMenu()
                }
                DateRangePickerView(selection: $selectedTimeRange)
                HStack(spacing: 15) {
                    HelperStatusBanner(helperManager: helperManager)
                }
                .padding()
                .materialChartCard(accent: helperManager.status == .enabled ? MaterialChartPalette.tertiary : MaterialChartPalette.warning)

                HeroMetricsView(viewModel: viewModel)

                ComponentPowerBreakdownView(viewModel: viewModel)

                BatteryHistoryView(historyViewModel: historyViewModel)

                LazyVGrid(columns: mainGridLayout, spacing: 20) {
                    MaxCapacityGraphCard(viewModel: viewModel, historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    CycleCountGraphCard(viewModel: viewModel, historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    TemperatureGraphCard(viewModel: viewModel, historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    PowerTimeHistoryGraphView(historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    BatteryHealthCard(viewModel: viewModel)
                    BatterySpecsCard(viewModel: viewModel)
                    PowerAdapterSpecsCard(viewModel: viewModel)
                    SignificantEnergyUsersView(viewModel: energyViewModel)
                }
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 25)
        }
        .onAppear {
            viewModel.start(highFrequency: true)
            StatsManager.shared.setPolling(for: "BatterySettingsView", requiredStats: [.batteryPower], interval: .seconds(1))
            historyViewModel.fetchHistory(filtering: selectedTimeRange)
            energyViewModel.start()
        }
        .onDisappear {
            tearDownBatteryStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sapphireSettingsWillClose)) { _ in
            tearDownBatteryStats()
        }
        .onReceive(BatteryDataLogger.shared.entriesDidChange) { _ in
            historyViewModel.fetchHistory(filtering: selectedTimeRange)
        }
        .onChange(of: selectedTimeRange) { _, newRange in
            historyViewModel.filterData(for: newRange)
        }
    }

    private func tearDownBatteryStats() {
        energyViewModel.stop()
        viewModel.stop()
        historyViewModel.releaseMemory()
        StatsManager.shared.setPolling(for: "BatterySettingsView", requiredStats: [])
    }
}

struct BatterySpecsCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject private var statsManager = StatsManager.shared
    @ObservedObject private var powerModeManager = PowerModeManager.shared

    private var systemLoad: Double {
        statsManager.currentStats?.systemPower ?? abs(viewModel.powerConsumption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(MaterialChartPalette.warning)
                Text("Battery Specs").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Spacer()
            SpecRow(label: String(localized: "battery.current"), value: String(format: "%.1f A", Double(abs(viewModel.amperage)) / 1000.0))
            SpecRow(label: "Voltage", value: String(format: "%.1f V", viewModel.voltage / 1000.0))
            SpecRow(label: "Power", value: String(format: "%.0f W", abs(viewModel.powerConsumption)))
            SpecRow(label: "System Load", value: String(format: "%.2f W", systemLoad))

            HStack {
                Text("Low Power Mode").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    if powerModeManager.isLowPowerModeActive {
                        powerModeManager.disableLowPowerMode()
                    } else {
                        powerModeManager.enableLowPowerMode()
                    }
                }) {
                    Text(powerModeManager.isLowPowerModeActive ? "Enabled" : "Disabled")
                        .font(.system(size: 12)).fontWeight(.medium)
                        .foregroundColor(powerModeManager.isLowPowerModeActive ? .green : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (powerModeManager.isLowPowerModeActive ? Color.green.opacity(0.15) : Color.white.opacity(0.08)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(16)
        .materialChartCard(height: 180, accent: MaterialChartPalette.warning)
        .onAppear {
            statsManager.setPolling(for: "BatterySettings", requiredStats: [.systemPower, .batteryPower])
            _ = powerModeManager.isLowPowerModeEnabled()
        }
        .onDisappear {
            statsManager.setPolling(for: "BatterySettings", requiredStats: [])
        }
    }
}

private extension Array where Element == BatteryLogEntry {
    func closest(to date: Date) -> BatteryLogEntry? {
        self.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
    }
}

private struct BatteryMetricGraphCard<Value: Plottable & Comparable>: View {
    let title: String
    let currentValue: String
    let color: Color
    let chartData: [BatteryLogEntry]
    @Binding var selectedTimeRange: TimeRange
    let yDomain: ClosedRange<Value>
    let yAxisMarkCount: Int
    let metricLabel: String
    let metricValue: (BatteryLogEntry) -> Value
    let annotationText: (BatteryLogEntry) -> String

    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString(title, comment: "Settings title")).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text(currentValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.14))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Spacer()

            if chartData.isEmpty {
                EmptyStatsView(height: 150)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(chartData) { entry in
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value(metricLabel, metricValue(entry))
                        )
                        .foregroundStyle(MaterialChartPalette.lineGradient(for: color))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                        AreaMark(
                            x: .value("Time", entry.timestamp),
                            y: .value(metricLabel, metricValue(entry))
                        )
                        .foregroundStyle(MaterialChartPalette.tonalGradient(for: color))
                        .interpolationMethod(.linear)
                    }

                    if let selectedDate, let entry = chartData.closest(to: selectedDate) {
                        PointMark(
                            x: .value("Time", entry.timestamp),
                            y: .value(metricLabel, metricValue(entry))
                        )
                        .foregroundStyle(color)
                        .symbolSize(80)

                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(MaterialChartPalette.outline)
                            .annotation(position: .top, alignment: .center) {
                                MaterialSelectionPill(text: annotationText(entry), color: color)
                            }
                    }
                }
                .materialChartPlotStyle()
                .chartYScale(domain: yDomain)
                .dynamicXAxis(for: selectedTimeRange, isVisible: true)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: yAxisMarkCount)) }
                .chartXSelection(value: $selectedDate)
                .frame(height: 150)
                .padding(.horizontal, 12)
            }

            Spacer()
        }
        .materialChartCard(height: 220)
    }
}

struct MaxCapacityGraphCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange

    var body: some View {
        let chartData = historyViewModel.chartData.filter { $0.maxCapacity > 0 }
        let capacities = chartData.map(\.maxCapacity)

        BatteryMetricGraphCard(
            title: "Max Capacity",
            currentValue: "\(viewModel.maxCapacityPercentage)%",
            color: MaterialChartPalette.primary,
            chartData: chartData,
            selectedTimeRange: $selectedTimeRange,
            yDomain: ((capacities.min() ?? 0) - 50)...((capacities.max() ?? 8000) + 50),
            yAxisMarkCount: 3,
            metricLabel: "Capacity",
            metricValue: { $0.maxCapacity },
            annotationText: { "\($0.maxCapacity) mAh" }
        )
    }
}

struct CycleCountGraphCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange

    var body: some View {
        let chartData = historyViewModel.chartData.filter { $0.cycleCount > 0 }
        let cycles = chartData.map(\.cycleCount)

        BatteryMetricGraphCard(
            title: "Cycle Count",
            currentValue: "\(viewModel.cycleCount)",
            color: MaterialChartPalette.secondary,
            chartData: chartData,
            selectedTimeRange: $selectedTimeRange,
            yDomain: ((cycles.min() ?? 0) - 10)...((cycles.max() ?? 1000) + 10),
            yAxisMarkCount: 3,
            metricLabel: "Cycles",
            metricValue: { $0.cycleCount },
            annotationText: { "\($0.cycleCount) cycles" }
        )
    }
}

struct TemperatureGraphCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange

    var body: some View {
        BatteryMetricGraphCard(
            title: "Temperature",
            currentValue: String(format: "%.1f °C", viewModel.temperature),
            color: MaterialChartPalette.error,
            chartData: historyViewModel.chartData.filter { $0.temperature > 0 },
            selectedTimeRange: $selectedTimeRange,
            yDomain: 20...55,
            yAxisMarkCount: 4,
            metricLabel: "Temp",
            metricValue: { $0.temperature },
            annotationText: { String(format: "%.1f °C", $0.temperature) }
        )
    }
}

struct PowerTimeHistoryGraphView: View {
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange
    @State private var selectedDate: Date?

    var body: some View {
        let powerData = historyViewModel.chartData.filter { $0.powerConsumption > 0 }
        let timeData = historyViewModel.chartData.filter { $0.timeRemainingMinutes > 0 }

        VStack(alignment: .leading, spacing: 0) {
            Text("Power & Time")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.top, 16)

            Spacer()

            if powerData.isEmpty && timeData.isEmpty {
                EmptyStatsView(height: 150)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(powerData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Power", entry.powerConsumption))
                            .foregroundStyle(by: .value("Metric", "Power (W)"))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    ForEach(timeData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Time", Double(entry.timeRemainingMinutes) / 60.0))
                            .foregroundStyle(by: .value("Metric", "Time (h)"))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }

                    if let selectedDate {
                        if let powerEntry = powerData.closest(to: selectedDate) {
                            PointMark(x: .value("Time", powerEntry.timestamp), y: .value("Power", powerEntry.powerConsumption))
                                .foregroundStyle(MaterialChartPalette.primary)
                                .symbolSize(80)
                        }
                        if let timeEntry = timeData.closest(to: selectedDate) {
                            PointMark(x: .value("Time", timeEntry.timestamp), y: .value("Time", Double(timeEntry.timeRemainingMinutes) / 60.0))
                                .foregroundStyle(MaterialChartPalette.tertiary)
                                .symbolSize(80)
                        }

                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(MaterialChartPalette.outline)
                            .annotation(position: .top, alignment: .center) {
                                annotationView(for: selectedDate, powerData: powerData, timeData: timeData)
                            }
                    }
                }
                .materialChartPlotStyle()
                .chartForegroundStyleScale([
                    "Power (W)": MaterialChartPalette.primary,
                    "Time (h)": MaterialChartPalette.tertiary
                ])
                .dynamicXAxis(for: selectedTimeRange, isVisible: true)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartXSelection(value: $selectedDate)
                .frame(height: 150)
                .padding(.horizontal, 12)
            }

            Spacer()
        }
        .materialChartCard(height: 220)
    }

    @ViewBuilder
    private func annotationView(for date: Date, powerData: [BatteryLogEntry], timeData: [BatteryLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let powerEntry = powerData.closest(to: date) {
                Text(String(format: "%.2f W", powerEntry.powerConsumption))
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            if let timeEntry = timeData.closest(to: date) {
                Text(String(format: "%.1f h", Double(timeEntry.timeRemainingMinutes) / 60.0))
                    .font(.caption)
                    .foregroundColor(.mint)
            }
        }
        .padding(4)
        .background(.background)
        .cornerRadius(4)
    }

}

struct BatteryHistoryView: View {
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @State private var selectedEntry: BatteryLogEntry?
    @State private var hoveredDate: Date?

    private var hoveredEntry: BatteryLogEntry? {
        guard let hoveredDate else { return nil }
        return historyViewModel.chartData.closest(to: hoveredDate)
    }

    private var summaryStats: (min: Int, max: Int, avg: Int, avgTemp: Double, avgPower: Double)? {
        let data = historyViewModel.chartData
        guard !data.isEmpty else { return nil }
        let charges = data.map(\.charge)
        let temps = data.map(\.temperature).filter { $0 > 0 }
        let powers = data.map(\.powerConsumption).filter { $0 > 0 }
        return (
            min: charges.min() ?? 0,
            max: charges.max() ?? 0,
            avg: Int((Double(charges.reduce(0, +)) / Double(charges.count)).rounded()),
            avgTemp: temps.isEmpty ? 0 : temps.reduce(0, +) / Double(temps.count),
            avgPower: powers.isEmpty ? 0 : powers.reduce(0, +) / Double(powers.count)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battery Usage History")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    if !historyViewModel.chartData.isEmpty {
                        Text("\(historyViewModel.chartData.count) data points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let stats = summaryStats {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            StatPill(label: "Min", value: "\(stats.min)%", color: MaterialChartPalette.warning)
                            StatPill(label: "Avg", value: "\(stats.avg)%", color: MaterialChartPalette.primary)
                            StatPill(label: "Max", value: "\(stats.max)%", color: MaterialChartPalette.tertiary)
                            if stats.avgTemp > 0 {
                                StatPill(label: "Temp", value: String(format: "%.0f°", stats.avgTemp), color: MaterialChartPalette.error)
                            }
                            if stats.avgPower > 0 {
                                StatPill(label: "Draw", value: String(format: "%.1fW", stats.avgPower), color: MaterialChartPalette.warning)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            historyLegend
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if historyViewModel.isLoading {
                ProgressView()
                    .frame(height: 320, alignment: .center)
                    .frame(maxWidth: .infinity)
            } else if historyViewModel.chartData.isEmpty {
                EmptyHistoryView()
            } else {
                chartView
                    .frame(height: 320)
                    .padding(.horizontal, 20)

                if let entry = selectedEntry {
                    BatteryDataPointCard(entry: entry, onDismiss: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedEntry = nil
                        }
                    })
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, 20)
        .materialChartCard()
        .animation(.easeOut(duration: 0.2), value: selectedEntry?.id)
    }

    private var historyLegend: some View {
        HStack(spacing: 10) {
            legendChip(label: "Charging", color: MaterialChartPalette.tertiary)
            legendChip(label: "Paused", color: MaterialChartPalette.primary)
            legendChip(label: "On Battery", color: MaterialChartPalette.warning)
            legendChip(label: "Low", color: MaterialChartPalette.error)
            Spacer(minLength: 0)
            Text("Line color = status")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MaterialChartPalette.onSurfaceVariant.opacity(0.75))
        }
    }

    private func legendChip(label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: 3)
            Text(NSLocalizedString(label, comment: "Settings label"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                .lineLimit(1)
        }
        .frame(width: 100)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MaterialChartPalette.surfaceContainer, in: Capsule())
    }

    private var chargeLineSegments: [(id: String, color: Color, a: BatteryLogEntry, b: BatteryLogEntry)] {
        let data = historyViewModel.chartData
        guard data.count >= 2 else { return [] }

        var segments: [(id: String, color: Color, a: BatteryLogEntry, b: BatteryLogEntry)] = []
        segments.reserveCapacity(data.count - 1)
        for i in 0..<(data.count - 1) {
            let a = data[i]
            let b = data[i + 1]
            segments.append((
                id: "\(a.id.uuidString)-\(b.id.uuidString)",
                color: statusColor(for: a),
                a: a,
                b: b
            ))
        }
        return segments
    }

    private var chartView: some View {
        Chart {
            ForEach(historyViewModel.chartData) { entry in
                AreaMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Charge", entry.charge)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)
            }

            ForEach(chargeLineSegments, id: \.id) { segment in
                LineMark(
                    x: .value("Time", segment.a.timestamp),
                    y: .value("Charge", segment.a.charge),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(segment.color)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value("Time", segment.b.timestamp),
                    y: .value("Charge", segment.b.charge),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(segment.color)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
            }

            if let entry = hoveredEntry ?? selectedEntry {
                RuleMark(x: .value("Selected", entry.timestamp))
                    .foregroundStyle(MaterialChartPalette.outlineStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Charge", entry.charge)
                )
                .foregroundStyle(statusColor(for: entry))
                .symbolSize(selectedEntry?.id == entry.id ? 120 : 90)
                .annotation(position: .top, spacing: 6) {
                    if selectedEntry == nil {
                        MaterialSelectionPill(
                            text: "\(entry.charge)% · \(entry.timestamp.formatted(date: .omitted, time: .shortened))",
                            color: statusColor(for: entry)
                        )
                    }
                }
            }
        }
        .materialChartPlotStyle()
        .chartYScale(domain: 0...108)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(MaterialChartPalette.outline.opacity(0.7))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(MaterialChartPalette.outline)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, style: .time)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    }
                }
            }
        }
        .chartXSelection(value: $hoveredDate)
        .simultaneousGesture(TapGesture().onEnded {
            if let entry = hoveredEntry {
                withAnimation(.easeOut(duration: 0.18)) {
                    if selectedEntry?.id == entry.id {
                        selectedEntry = nil
                    } else {
                        selectedEntry = entry
                    }
                }
            }
        })
        .padding(.bottom, 8)
    }

    private func statusColor(for entry: BatteryLogEntry) -> Color {
        if entry.isCharging && entry.isPluggedIn { return MaterialChartPalette.tertiary }
        if entry.isPluggedIn && !entry.isCharging { return MaterialChartPalette.primary }
        if entry.charge <= 20 && !entry.isPluggedIn { return MaterialChartPalette.error }
        if !entry.isPluggedIn { return MaterialChartPalette.warning }
        return MaterialChartPalette.primary
    }
}
struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString(label, comment: "Settings label"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(12)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No History Data")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Battery usage data will appear here once collected")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(height: 320)
        .frame(maxWidth: .infinity)
    }
}

struct BatteryDataPointCard: View {
    let entry: BatteryLogEntry
    let onDismiss: () -> Void

    private var statusLabel: String {
        if entry.isCharging && entry.isPluggedIn { return "Charging" }
        if entry.isPluggedIn && !entry.isCharging { return "Charge Paused" }
        if entry.charge <= 20 { return "Low Battery" }
        if !entry.isPluggedIn { return "On Battery" }
        return "Normal"
    }

    private var statusColor: Color {
        if entry.isCharging && entry.isPluggedIn { return MaterialChartPalette.tertiary }
        if entry.isPluggedIn && !entry.isCharging { return MaterialChartPalette.primary }
        if entry.charge <= 20 { return MaterialChartPalette.error }
        if !entry.isPluggedIn { return MaterialChartPalette.warning }
        return MaterialChartPalette.onSurfaceVariant
    }

    private var timeRemainingText: String {
        guard entry.timeRemainingMinutes > 0 else { return "—" }
        let hours = entry.timeRemainingMinutes / 60
        let minutes = entry.timeRemainingMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private var ledLabel: String {
        switch entry.ledColor {
        case 1: return "Green"
        case 2: return "Amber"
        case 3: return "Red"
        case 0: return "Off"
        default: return "\(entry.ledColor)"
        }
    }

    private var detailRows: [(section: String, rows: [(icon: String, label: String, value: String, color: Color)])] {
        [
            ("Charge", [
                ("battery.100", "Charge", "\(entry.charge)%", statusColor),
                ("cpu", "Hardware Charge", "\(entry.hardwareCharge)%", MaterialChartPalette.primary),
                ("heart.fill", "Max Capacity", "\(entry.maxCapacity) mAh", .pink),
                ("arrow.clockwise", "Cycle Count", "\(entry.cycleCount)", MaterialChartPalette.secondary),
            ]),
            ("Power", [
                ("bolt.fill", "Power Draw", entry.powerConsumption > 0 ? String(format: "%.2f W", entry.powerConsumption) : "—", MaterialChartPalette.warning),
                ("clock.fill", entry.isCharging ? "Time to Full" : "Time Remaining", timeRemainingText, MaterialChartPalette.primary),
                ("thermometer.medium", "Temperature", String(format: "%.1f °C", entry.temperature), entry.temperature > 40 ? MaterialChartPalette.error : MaterialChartPalette.tertiary),
            ]),
            ("State", [
                ("powerplug.fill", "Adapter", entry.isPluggedIn ? "Connected" : "Unplugged", entry.isPluggedIn ? MaterialChartPalette.tertiary : .gray),
                ("bolt.circle", "Charging", entry.isCharging ? "Yes" : "No", entry.isCharging ? MaterialChartPalette.tertiary : .gray),
                ("slider.horizontal.3", "Management", entry.managementState.rawValue, MaterialChartPalette.secondary),
                ("leaf.fill", "Low Power Mode", entry.isLowPowerMode ? "On" : "Off", entry.isLowPowerMode ? MaterialChartPalette.warning : .gray),
            ]),
            ("System", [
                ("display", "Screen", entry.isScreenOn ? "On" : "Off", entry.isScreenOn ? MaterialChartPalette.primary : .gray),
                ("moon.fill", "Sleeping", entry.isSleeping ? "Yes" : "No", entry.isSleeping ? MaterialChartPalette.secondary : .gray),
                ("light.max", "LED", ledLabel, MaterialChartPalette.onSurfaceVariant),
                ("calendar", "Logged", entry.timestamp.formatted(date: .abbreviated, time: .standard), MaterialChartPalette.onSurfaceVariant),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.charge)%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                        .monospacedDigit()
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                }

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.16), in: Capsule())

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .background(MaterialChartPalette.surfaceContainer, in: Circle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(detailRows, id: \.section) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.section.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                            .tracking(0.6)

                        VStack(spacing: 0) {
                            ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                                BatteryAlignedDetailRow(
                                    icon: row.icon,
                                    label: row.label,
                                    value: row.value,
                                    color: row.color
                                )
                                if index < section.rows.count - 1 {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            MaterialChartPalette.surfaceContainer,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(MaterialChartPalette.surfaceContainer.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MaterialChartPalette.outline, lineWidth: 1)
        )
    }
}

private struct BatteryAlignedDetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
            Text(NSLocalizedString(label, comment: "Settings label"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }
}

struct BatteryHealthCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                Text("Battery Health").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Spacer()
            SpecRow(label: "Design Capacity", value: "\(viewModel.designCapacity) mAh", percentage: "100%")
            SpecRow(label: "Maximum Capacity", value: "\(viewModel.maxCapacity) mAh", percentage: "\(viewModel.maxCapacityPercentage)%")
            SpecRow(label: "macOS Capacity", value: "\(viewModel.appleMaxCapacity) mAh", percentage: "\(viewModel.appleMaxCapacityPercentage)%")
            SpecRow(label: "macOS Condition", value: viewModel.health)
            SpecRow(label: "Cycle Count", value: "\(viewModel.cycleCount)")
            Spacer()
        }
        .padding(16)
        .materialChartCard(height: 180, accent: .pink)
    }
}

struct PowerAdapterSpecsCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "powerplug.fill")
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                Text("Power Adapter Specs")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            if let info = viewModel.powerAdapterInfo, info.maxPower > 0 {
                if info.current > 0 || info.maxCurrent > 0 {
                    PowerAdapterSpecRow(
                        label: String(localized: "battery.current"),
                        currentValue: info.current > 0 ? "\(Double(info.current) / 1000.0, default: "%.2f") A" : "0.0 A",
                        maxValue: info.maxCurrent > 0 ? "\(Double(info.maxCurrent) / 1000.0, default: "%.1f") A" : "N/A"
                    )
                }

                if info.voltage > 0 || info.maxVoltage > 0 {
                    PowerAdapterSpecRow(
                        label: "Voltage",
                        currentValue: info.voltage > 0 ? "\(Double(info.voltage) / 1000.0, default: "%.1f") V" : "0.0 V",
                        maxValue: info.maxVoltage > 0 ? "\(Double(info.maxVoltage) / 1000.0, default: "%.1f") V" : "N/A"
                    )
                }

                PowerAdapterSpecRow(
                    label: "Power",
                    currentValue: "\(Double(info.power), default: "%.1f") W",
                    maxValue: "\(info.maxPower) W"
                )

                if !info.name.isEmpty && info.name != "N/A" {
                    SpecRow(label: "Name", value: info.name)
                }

                if !info.manufacturer.isEmpty && info.manufacturer != "N/A" {
                    SpecRow(label: "Manufacturer", value: info.manufacturer)
                }

                if !info.serialNumber.isEmpty && info.serialNumber != "N/A" {
                    SpecRow(label: "Serial Number", value: info.serialNumber)
                }
            } else {
                Text("Not Connected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .materialChartCard(minHeight: 180, accent: .gray)
    }
}

fileprivate struct PowerAdapterSpecRow: View {
    let label: String
    let currentValue: String
    let maxValue: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(NSLocalizedString(label, comment: "Settings label"))
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(currentValue)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
            Text("of")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
            Text(maxValue)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
        }
    }
}

struct SignificantEnergyUsersView: View {
    @ObservedObject var viewModel: EnergyViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Significant Energy Users")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            if viewModel.topProcesses.isEmpty {
                Text("No Apps Using Significant Energy")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.topProcesses) { process in
                    HStack {
                        Text(process.name).font(.caption)
                        Spacer()
                        Text(String(format: "%.2f%%", process.usage))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MaterialChartPalette.primary.opacity(0.14), in: Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .materialChartCard(height: 180, accent: MaterialChartPalette.primary)
    }
}
struct EmptyStatsView: View {
    var height: CGFloat
    var body: some View {
        VStack {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundColor(.secondary.opacity(0.3))
            Text("No History Yet").font(.caption).foregroundColor(.secondary)
        }
        .frame(height: height).frame(maxWidth: .infinity)
    }
}

struct HealthStatRow: View {
    let label: String, value: String, percentage: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(NSLocalizedString(label, comment: "Settings label")).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing)
            Text("\(percentage)%").font(.caption.weight(.semibold)).frame(width: 35, alignment: .trailing)
        }
    }
}
struct SimpleHealthStatRow: View {
    let label: String, value: String
    var body: some View {
        HStack {
            Text(NSLocalizedString(label, comment: "Settings label")).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold))
        }
    }
}

struct PowerRow: View {
    let label: String, value: String, color: Color?
    var body: some View {
        HStack {
            Text(NSLocalizedString(label, comment: "Settings label")).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold)).foregroundColor(color ?? .primary)
        }
    }
}

struct BatteryConfigurationView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @EnvironmentObject var powerStateController: PowerStateController
    @StateObject private var helperManager = HelperManager.shared
    @ObservedObject private var calibrationManager = CalibrationManager.shared
    @State private var showingScheduleSheet = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 15) {
                    HelperStatusBanner(helperManager: helperManager)
                }
                .padding()
                .roundedCard(fill: Color.black.opacity(0.15), cornerRadius: 20, stroke: Color.white.opacity(0.1))
                .onAppear { helperManager.checkIfRunning() }

                notificationsSection
                coreFeaturesSection
                chargingAndSleepSection
                automaticDischargeSection
                OneTimeDischargeView()
                schedulingSection
                CalibrationView()
                advancedSection
                FanControlSectionView()
            }
            .padding(.horizontal, 25).padding(.bottom, 25)
        }
        .sheet(isPresented: $showingScheduleSheet) {
            ScheduleView().environmentObject(settings)
        }
    }

    @ViewBuilder private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications & Live Activity").font(.headline).padding([.top, .horizontal])
            CustomSliderRowView(label: "Notify when battery is below", value: Binding(get: { Double(settings.settings.lowBatteryNotificationPercentage) }, set: { settings.settings.lowBatteryNotificationPercentage = Int($0) }), range: 10...50, specifier: "%.0f %%")
            Divider().padding(.leading, 20)
            ToggleRow(title: "Play Sound for Low Battery Alert", description: "Get an audible alert when your battery is running low.", isOn: $settings.settings.lowBatteryNotificationSoundEnabled)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Prompt to Turn on Low Power Mode", description: "Show a convenient button to enable Low Power Mode when your battery gets low.", isOn: $settings.settings.promptForLowPowerMode)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Show Estimated Time Remaining", description: "Display the estimated time to full (when charging) or time to empty (when on battery) in the live activity.", isOn: $settings.settings.showEstimatedBatteryTime)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var coreFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Battery Management Features").font(.headline).padding([.top, .horizontal])
            CustomSliderRowView(label: "Charge Limit", value: Binding(get: { Double(settings.settings.batteryChargeLimit) }, set: { settings.settings.batteryChargeLimit = Int($0) }), range: 50...100, specifier: "%.0f %%")
            Divider().padding(.leading, 20)
            ToggleRow(title: "Sailing Mode", description: "Prevents battery wear from constant micro-charging cycles when plugged in for long periods. Charging will pause at the limit and only resume when the battery drops by a set amount.", isOn: $settings.settings.sailingModeEnabled)
            if settings.settings.sailingModeEnabled {
                 CustomSliderRowView(label: "Resume charging below", value: Binding(get: { Double(settings.settings.sailingModeLowerLimit) }, set: { settings.settings.sailingModeLowerLimit = Int($0) }), range: 5...20, specifier: "%.0f%% below limit")
            }
            Divider().padding(.leading, 20)
            ToggleRow(title: "Heat Protection", description: "Automatically pauses charging if the battery temperature gets too high to prevent heat-related damage and extend its lifespan.", isOn: $settings.settings.heatProtectionEnabled)
            if settings.settings.heatProtectionEnabled {
                 CustomSliderRowView(label: "Pause charging above", value: $settings.settings.heatProtectionThreshold, range: 35...50, specifier: "%.0f °C")
            }
        }
        .modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.sailingModeEnabled || settings.settings.heatProtectionEnabled)
    }

    @ViewBuilder private var automaticDischargeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Automatic Discharge").font(.headline).padding([.top, .horizontal])
            ToggleRow(
                title: "Enable Automatic Discharge",
                description: "When enabled, your Mac will stop using AC power and run from its battery until the battery limit is reached.",
                isOn: $settings.settings.dischargeToLimitEnabled
            )
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var chargingAndSleepSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Charging & Sleep").font(.headline).padding([.top, .horizontal])
            InfoContainer(text: "Although functionality is in place to keep the battery management functinal even when the device is sleeping it may not always work. Use these settings if you want to be certain of the behaviour when the device is sleeping.", iconName: "info.circle", color: .yellow).padding()
            ToggleRow(title: "Stop charging when sleeping", description: "Prevents your Mac from sitting at 100% charge overnight, which can degrade the battery over time. Charging resumes on wake.", isOn: $settings.settings.stopChargingWhenSleeping)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Log battery during sleep", description: "Wakes the Mac briefly (display stays off) at a set interval to record battery state and re-assert your charge limit overnight. Sleep is never disabled.", isOn: $settings.settings.logBatteryDuringSleep)
            if settings.settings.logBatteryDuringSleep {
                CustomSliderRowView(label: "Log every", value: Binding(get: { Double(settings.settings.sleepLoggingIntervalMinutes) }, set: { settings.settings.sleepLoggingIntervalMinutes = Int($0) }), range: 15...120, specifier: "%.0f min")
            }
            Divider().padding(.leading, 20)
            ToggleRow(title: "Stop charging when app closed", description: "The helper tool ensures your charging rules are still applied even if the Sapphire app isn't running.", isOn: .constant(true)).disabled(true)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Disable Sleep until Charge Limit", description: "Keeps your Mac awake to ensure it reaches the charge limit, useful for 'top-up' schedules before you need to leave.", isOn: $settings.settings.disableSleepUntilChargeLimit)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scheduling").font(.headline).padding([.top, .horizontal])
            InfoContainer(text: "Automate charging behaviors and perform manual or scheduled calibrations to keep your battery's readings accurate.", iconName: "calendar.badge.clock", color: .cyan).padding()
            Divider().padding(.horizontal)
            HStack {
                Text("Manage Schedule").font(.subheadline.bold())
                Spacer()
                Button("Open Scheduler") { showingScheduleSheet = true }.buttonStyle(.bordered)
            }.padding()
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Advanced").font(.headline).padding([.top, .horizontal])
            ToggleRow(title: "Use Hardware Battery Percentage", description: "Reads the 'true' charge from the battery controller, which can be more accurate but may differ from what macOS shows.", isOn: $settings.settings.useHardwareBatteryPercentage)
        }.modifier(SettingsContainerModifier())
    }
}

struct OneTimeDischargeView: View {
    @EnvironmentObject private var settings: SettingsEditingSession
    @StateObject private var batteryMonitor = BatteryMonitor.shared

    private var dischargeProgress: Double {
        guard let currentCharge = batteryMonitor.currentState?.level else { return 0 }

        let targetCharge = Double(settings.settings.oneTimeDischargeTarget)
        let initialCharge = 100.0

        let totalRange = initialCharge - targetCharge
        guard totalRange > 0 else { return 1.0 }

        let dischargedAmount = initialCharge - Double(currentCharge)
        let progress = dischargedAmount / totalRange

        return max(0.0, min(1.0, progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One-Time Discharge").font(.headline).padding([.top, .horizontal])
            InfoContainer(
                text: "Temporarily discharge to a specific percentage. This will not affect your main charge limit or automatic discharge settings.",
                iconName: "target",
                color: .blue
            ).padding()

            if settings.settings.oneTimeDischargeEnabled {
                VStack(spacing: 12) {
                    Text("Discharging to \(settings.settings.oneTimeDischargeTarget)%...")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ProgressView(value: dischargeProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    if let currentCharge = batteryMonitor.currentState?.level {
                        Text("Current: \(currentCharge)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Stop", role: .destructive) {
                        settings.settings.oneTimeDischargeEnabled = false
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 5)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(minHeight: 120)

            } else {
                VStack(spacing: 15) {
                    Stepper(
                        "Discharge Target: \(settings.settings.oneTimeDischargeTarget)%",
                        value: $settings.settings.oneTimeDischargeTarget,
                        in: 1...95,
                        step: 5
                    )

                    Button(action: {
                        settings.settings.oneTimeDischargeEnabled = true
                    }) {
                        Text("Start One-Time Discharge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(minHeight: 120)
            }
        }
        .modifier(SettingsContainerModifier())
    }
}

fileprivate extension TimeInterval {
    func formatted() -> String {
        SettingsDurationFormatter.hourMinute.string(from: self) ?? "0m"
    }
}

private enum SettingsDurationFormatter {
    static let hourMinute: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct ScheduleView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @State private var showingAddTask = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Schedule Automation").font(.largeTitle.bold())

            VStack {
                HStack {
                    Text("Scheduled Tasks").font(.headline)
                    Spacer()
                    Button(action: { showingAddTask = true }) { Image(systemName: "plus") }
                }.padding([.horizontal, .top])

                if settings.settings.scheduledTasks.isEmpty {
                    Text("No tasks scheduled.").foregroundColor(.secondary).padding()
                } else {
                    List {
                        ForEach($settings.settings.scheduledTasks) { $task in
                            TaskRowView(task: $task).listRowBackground(Color.clear)
                        }.onDelete { indexSet in settings.settings.scheduledTasks.remove(atOffsets: indexSet) }
                    }.listStyle(.plain).background(Color.clear)
                }
            }.modifier(SettingsContainerModifier())

            VStack(alignment: .leading) {
                 Text("Task History").font(.headline).padding([.horizontal, .top])
                 List(scheduleManager.taskHistory) { event in
                     HStack {
                         Text(event.taskDescription); Spacer(); Text(event.timestamp, style: .time)
                     }.listRowBackground(Color.clear)
                 }.listStyle(.plain).background(Color.clear)
            }.modifier(SettingsContainerModifier())

            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(30).frame(minWidth: 500, minHeight: 600)
        .sheet(isPresented: $showingAddTask) {
            AddTaskView().environmentObject(settings)
        }
    }
}

struct TaskRowView: View {
    @Binding var task: ScheduledTask

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.action.displayName).font(.headline)

                switch task.action {
                case .setChargeLimit, .dischargeTo:
                    Text("Target: \(task.chargeLimit)% | Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                case .setFanConstant:
                    Text("Speed: \(task.fanSpeed) RPM | Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                case .setFanSensorBased:
                    Text("Sensor: \(SensorNameMap.name(for: task.sensorKey)) (\(task.minTemp)°C-\(task.maxTemp)°C) | Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                default:
                    Text("Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $task.isActive).labelsHidden()
        }
    }
}

struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var fanManager = FanManager.shared
    @State private var newTask = ScheduledTask()

    private var firstFan: FanInfo? { fanManager.fans.first }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Scheduled Task").font(.title.bold())

            VStack(spacing: 15) {
                Picker("Action:", selection: $newTask.action) {
                    ForEach(TaskAction.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: newTask.action) {
                    if newTask.action == .setFanSensorBased, newTask.sensorKey.isEmpty {
                        newTask.sensorKey = fanManager.sensors.first?.key ?? ""
                    }
                }

                if [.setChargeLimit, .dischargeTo].contains(newTask.action) {
                    CustomSliderRowView(label: "Target Charge", value: Binding(get: { Double(newTask.chargeLimit) }, set: { newTask.chargeLimit = Int($0) }), range: 20...100, specifier: "%.0f%%")
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }

                if newTask.action == .setFanConstant {
                    if let fan = firstFan {
                        CustomSliderRowView(label: "Target Speed", value: Binding(get: { Double(newTask.fanSpeed) }, set: { newTask.fanSpeed = Int($0) }), range: Double(fan.minRPM)...Double(fan.maxRPM), specifier: "%.0f RPM")
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }

                if newTask.action == .setFanSensorBased {
                    VStack(spacing: 15) {
                        Picker("Based on Sensor:", selection: $newTask.sensorKey) {
                            ForEach(fanManager.sensors) { sensor in
                                Text(sensor.name).tag(sensor.key)
                            }
                        }

                        CustomSliderRowView(label: "Start increasing from:", value: Binding(get: { Double(newTask.minTemp) }, set: { newTask.minTemp = Int($0) }), range: 20...90, specifier: "%.0f °C")

                        CustomSliderRowView(label: "Maximum temperature:", value: Binding(get: { Double(newTask.maxTemp) }, set: { newTask.maxTemp = Int($0) }), range: Double(newTask.minTemp)...100, specifier: "%.0f °C")
                    }
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }

                Picker("Repeat:", selection: $newTask.repeatInterval) {
                    ForEach(RepeatInterval.allCases) { Text($0.displayName).tag($0) }
                }

                DatePicker("Time:", selection: $newTask.startTime, displayedComponents: .hourAndMinute)
            }
            .padding().modifier(SettingsContainerModifier())
            .animation(.default, value: newTask.action)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add Task") {
                    settings.settings.scheduledTasks.append(newTask)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(30).frame(width: 450)
    }
}

struct HUDSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    private var hudCustomColorBinding: Binding<Color> {
        Binding(
            get: { settings.settings.hudCustomColor?.color ?? .accentColor },
            set: { settings.settings.hudCustomColor = CodableColor(color: $0) }
        )
    }

    private var pillStyleEnabled: Bool {
        settings.settings.effectiveVolumeHUDStyle == .pill || settings.settings.effectiveBrightnessHUDStyle == .pill
    }

    private var xdrBrightnessLevelBinding: Binding<Double> {
        Binding(
            get: { Double(settings.settings.xdrBrightnessLevel * 100) },
            set: { settings.settings.xdrBrightnessLevel = Float($0 / 100) }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("HUD")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                // MARK: HUD Appearance
                VStack(alignment: .leading, spacing: 0) {
                    Text("HUD Appearance")
                        .font(.headline)
                        .padding([.horizontal, .top])

                    Divider().padding(.top, 10).padding(.leading, 20)

                    HStack {
                        Text("Style")
                        Spacer()
                        Picker("", selection: $settings.settings.hudVisualStyle) {
                            ForEach(HUDVisualStyle.allCases) { style in
                                Text(style.id).tag(style)
                            }
                        }
                        .labelsHidden().frame(width: 150)
                    }.padding()

                    if settings.settings.hudVisualStyle == .color {
                        ColorPicker("Custom HUD Color", selection: hudCustomColorBinding)
                            .padding()
                            .transition(.opacity)
                    }

                    Divider().padding(.leading, 20)

                    CustomSliderRowView(label: "HUD Duration", value: $settings.settings.hudDuration, range: 1...10, specifier: "%.1f s")
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show Percentage", description: "", isOn: $settings.settings.hudShowPercentage)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show Function Name", description: "Display the HUD name (e.g. Volume, Brightness, Spotify) when the thin style is enabled.", isOn: $settings.settings.hudShowFunctionName)

                    if pillStyleEnabled {
                        Divider().padding(.leading, 20)
                        HStack {
                            Text("Pill Position")
                            Spacer()
                            Picker("", selection: $settings.settings.hudPillPosition) {
                                ForEach(PillHUDPosition.allCases) { position in
                                    Text(position.id).tag(position)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        .padding()
                        HStack {
                            Text("Pill Style")
                            Spacer()
                            Picker("", selection: $settings.settings.hudPillStyle) {
                                ForEach(PillHUDStyle.allCases) { style in
                                    Text(style.id).tag(style)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        .padding()
                        Divider().padding(.leading, 20)
                        CustomSliderRowView(label: "Pill Length", value: $settings.settings.hudPillLength, range: 160...460, specifier: "%.0f pt")
                        Divider().padding(.leading, 20)
                        CustomSliderRowView(label: "Pill Thickness", value: $settings.settings.hudPillThickness, range: 44...92, specifier: "%.0f pt")
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: pillStyleEnabled)
                .animation(.default, value: settings.settings.hudVisualStyle)

                // MARK: Spotify, App & Device Icons (essential)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Show Spotify, App & Device Icons")
                        .font(.headline)
                        .padding([.horizontal, .top])

                    Divider().padding(.top, 10).padding(.leading, 20)

                    ToggleRow(
                        title: "Show Spotify Device in HUD",
                        description: "Display a special HUD with the active device name when changing volume while Spotify is active.",
                        isOn: $settings.settings.showSpotifyVolumeHUD
                    )
                    Divider().padding(.leading, 20)
                    ToggleRow(
                        title: "Show App Volume in HUD",
                        description: "Press Option + Volume keys to adjust volume for the active app (excludes Spotify and Apple Music).",
                        isOn: $settings.settings.showAppVolumeHUD
                    )

                    if settings.settings.showAppVolumeHUD {
                        ToggleRow(
                            title: "Show in Normal Volume HUD",
                            description: "Display app volume in the normal volume HUD (like Spotify). When disabled, only shows with Option + Volume keys.",
                            isOn: $settings.settings.showAppVolumeInNormalHUD
                        )
                        .padding(.leading, 20)
                    }

                    Divider().padding(.leading, 20)
                    ToggleRow(
                        title: "Show Device Icon Instead of Speaker",
                        description: "For devices like HomePods, show a device-specific icon in the volume HUD.",
                        isOn: $settings.settings.volumeHUDShowDeviceIcon
                    )

                    if settings.settings.volumeHUDShowDeviceIcon {
                        ToggleRow(
                            title: "Exclude Built-in Speakers",
                            description: "Only show device icons for external audio devices like AirPods or HomePods.",
                            isOn: $settings.settings.excludeBuiltInSpeakersFromHUDIcon
                        )
                        .padding(.leading, 20)
                        .transition(.opacity)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.volumeHUDShowDeviceIcon)

                // MARK: Volume HUD
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Volume HUD")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.settings.enableVolumeHUD)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("View Style")
                        Spacer()
                        Picker("", selection: $settings.settings.volumeHUDStyle) {
                            ForEach(HUDStyle.allCases.filter { $0 != .dots }) { style in
                                Text(style.id).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .padding()
                    .disabled(!settings.settings.enableVolumeHUD || settings.settings.volumeHUDShowDots)
                    .opacity(settings.settings.enableVolumeHUD && !settings.settings.volumeHUDShowDots ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Show Dots",
                        description: "Display volume as a row of dots instead of a bar.",
                        isOn: $settings.settings.volumeHUDShowDots
                    )
                    .disabled(!settings.settings.enableVolumeHUD)
                    .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Sound on Change")
                        Spacer()
                        Toggle("", isOn: $settings.settings.volumeHUDSoundEnabled)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()
                    .disabled(!settings.settings.enableVolumeHUD)
                    .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Per-App Volume Uses System Volume Ceiling",
                        description: "When enabled, 100% app volume is capped by current system output volume.",
                        isOn: $settings.settings.perAppVolumeSystemDependent
                    )
                    .disabled(!settings.settings.enableVolumeHUD)
                    .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    CustomSliderRowView(label: "Slider step", value: Binding(get: { Double(settings.settings.volumesliderstep) }, set: { settings.settings.volumesliderstep = Int($0) }), range: 1...20, specifier: "%.0f")
                        .disabled(!settings.settings.enableVolumeHUD)
                        .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Per-device slider steps")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(MultiAudioManager.shared.availableOutputDevices, id: \.uid) { device in
                            HStack {
                                Text(device.name)
                                    .font(.system(size: 13))
                                Spacer()

                                Picker("", selection: Binding(get: {
                                    Double(settings.settings.volumesliderstepByDevice[device.uid] ?? settings.settings.volumesliderstep)
                                }, set: { newVal in
                                    settings.settings.volumesliderstepByDevice[device.uid] = Int(newVal)
                                })) {
                                    ForEach(1...20, id: \.self) { val in
                                        Text("\(val)").tag(Double(val))
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 120)

                                Button(action: {
                                    settings.settings.volumesliderstepByDevice.removeValue(forKey: device.uid)
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to global slider step")
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 10)
                    .disabled(!settings.settings.enableVolumeHUD)
                    .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)
                }
                .modifier(SettingsContainerModifier())

                // MARK: Brightness HUD
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Brightness HUD")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.settings.enableBrightnessHUD)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("View Style")
                        Spacer()
                        Picker("", selection: $settings.settings.brightnessHUDStyle) {
                            ForEach(HUDStyle.allCases.filter { $0 != .dots }) { style in
                                Text(style.id).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .padding()
                    .disabled(!settings.settings.enableBrightnessHUD || settings.settings.brightnessHUDShowDots)
                    .opacity(settings.settings.enableBrightnessHUD && !settings.settings.brightnessHUDShowDots ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Show Dots",
                        description: "Display brightness as a row of dots instead of a bar.",
                        isOn: $settings.settings.brightnessHUDShowDots
                    )
                    .disabled(!settings.settings.enableBrightnessHUD)
                    .opacity(settings.settings.enableBrightnessHUD ? 1.0 : 0.5)

                    Divider().padding(.leading, 20)

                    CustomSliderRowView(label: "Slider step", value: Binding(get: { Double(settings.settings.brightnessliderstep) }, set: { settings.settings.brightnessliderstep = Int($0) }), range: 1...10, specifier: "%.0f")
                        .padding(.bottom, 10)
                        .disabled(!settings.settings.enableBrightnessHUD)
                        .opacity(settings.settings.enableBrightnessHUD ? 1.0 : 0.5)
                }
                .modifier(SettingsContainerModifier())

                // MARK: XDR Brightness (essential)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("XDR Brightness")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.settings.enableXDRBrightness)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    Divider()

                    VStack {
                        ToggleRow(
                            title: "XDR Brightness Lock",
                            description: "Require holding the Command (⌘) key to increase the brightness in the XDR range.",
                            isOn: $settings.settings.xdrBrightnessLock
                        )

                        Divider()

                        CustomSliderRowView(
                            label: "Max XDR Brightness",
                            value: xdrBrightnessLevelBinding,
                            range: 100...Double(getDeviceMaxBrightness() * 100),
                            specifier: "%.0f%%"
                        )

                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Apple limits brightness to preserve battery life. While this feature is system-controlled and there are no known side-effects, you should use this feature at your own risk.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("This feature works best on devices with XDR displays (14in and 16in Macbook Pro's and Pro Display XDR). M4 Macbook Pro's already display this behaviour in bright environments like in direct sunlight, this feature will allow you to do it in any type of environment.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 5)
                    }
                    .disabled(!settings.settings.enableXDRBrightness)
                    .opacity(settings.settings.enableXDRBrightness ? 1.0 : 0.5)

                }
                .padding()
                .modifier(SettingsContainerModifier())
                .disabled(!settings.settings.enableBrightnessHUD)
                .opacity(settings.settings.enableBrightnessHUD ? 1.0 : 0.5)
                .animation(.easeInOut, value: settings.settings.enableBrightnessHUD)
                .animation(.easeInOut, value: settings.settings.enableXDRBrightness)

                RequiredPermissionsView(section: .hud)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct MusicSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    @State private var isPrivateApiLoading = false
    @State private var privateApiError: String?
    @State private var isPrivateAuth = false
    @State private var isOfficialAuth = false
    @State private var officialDisplayName: String?
    @State private var isTidalAuth = false
    @State private var tidalDisplayName: String?
    @State private var loginChallenge: LoginChallengeDetails?
    @State private var showTidalLogin = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Music").font(.largeTitle.bold()).padding(.bottom)

                VStack(spacing: 0) {
                    HStack {
                        Text("Media Source")
                        Spacer()
                        Picker("", selection: $settings.settings.mediaSource) {
                            ForEach(MediaSource.allCases) { source in Text(source.displayName).tag(source) }
                        }
                        .labelsHidden().frame(width: 180)
                    }.padding()
                    if settings.settings.mediaSource != .system {
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Prioritize Selected Source", description: "Only show media from your selected source, ignoring browsers and other apps.", isOn: $settings.settings.prioritizeMediaSource)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.mediaSource)

                if settings.settings.mediaSource == .system {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Show Now Playing From").font(.headline).padding([.horizontal, .top])
                        Text("Choose which apps can appear in the music widget and media switcher. All apps, including browsers, are on by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        AppTogglesListView(isEnabled: { app in mediaVisibilityBinding(for: app, isBrowser: app.isBrowser) })
                    }
                    .modifier(SettingsContainerModifier())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Gestures").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Swipe Left to Skip", description: "In the music live activity, swipe left on the album art to go to the next track.", isOn: $settings.settings.swipeToSkipMusic)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Swipe Right to Rewind", description: "Swipe right on the album art to go to the previous track.", isOn: $settings.settings.swipeToRewindMusic)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Invert Swipe Gestures", description: "Swipe right to skip and left to go back.", isOn: $settings.settings.invertMusicGestures)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Two-Finger Tap to Play/Pause", description: "Tap the album art with two fingers to toggle playback.", isOn: $settings.settings.twoFingerTapToPauseMusic)
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Hold Actions").font(.headline).padding([.top, .horizontal])
                    ToggleRow(
                        title: "Enable Hold Actions",
                        description: "Press and hold secondary player buttons (Queue, Devices, Like, Shuffle, Repeat) for an alternate action. Previous / Next / Play are tap-only unless you assign a hold action below. When this is off, Previous/Next still seek while held.",
                        isOn: $settings.settings.musicLongPressActionsEnabled
                    )
                    if settings.settings.musicLongPressActionsEnabled {
                        Divider().padding(.leading, 20)
                        Text("Secondary Buttons")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        ForEach(settings.settings.musicPlayerButtonOrder.compactMap { MusicLongPressTarget.from(buttonType: $0) }) { target in
                            MusicLongPressActionPickerRow(target: target)
                            Divider().padding(.leading, 20)
                        }
                        Text("Transport (optional)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        ForEach([MusicLongPressTarget.previous, .next, .playPause]) { target in
                            MusicLongPressActionPickerRow(target: target)
                            if target != .playPause {
                                Divider().padding(.leading, 20)
                            }
                        }
                    }
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Default Music App")
                        Spacer()
                        Picker("", selection: $settings.settings.defaultMusicPlayer) {
                            ForEach(DefaultMusicPlayer.allCases) { player in
                                Text(player.displayName)
                                    .tag(player)
                                    .disabled(!player.isAppInstalled && player.webURL == nil)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding()
                    Divider().padding(.leading, 20)
                    HStack { Text("Open detailed Music widget on live activity click"); Spacer(); SettingsSwitch(isOn: $settings.settings.musicOpenOnClick) }.padding()
                    Divider().padding(.leading, 20)
                    HStack { Text("Waveform is volume sensitive"); Spacer(); SettingsSwitch(isOn: $settings.settings.musicWaveformIsVolumeSensitive) }.padding()
                    Divider().padding(.leading, 20)
                    Text("Waveform Appearance").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Enable Gradient", description: "Apply a gradient based on the album art to the waveform.", isOn: $settings.settings.waveformUseGradient)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Use Static Waveform", description: "Show a non-animating waveform when music is playing.", isOn: $settings.settings.useStaticWaveform)
                    Divider().padding(.leading, 20)
                    CustomSliderRowView(label: "Number of Bars", value: Binding(get: { Double(settings.settings.waveformBarCount) }, set: { settings.settings.waveformBarCount = Int($0) }), range: 3...6, specifier: "%.0f")
                    Divider().padding(.leading, 20)
                    CustomSliderRowView(label: "Bar Thickness", value: $settings.settings.waveformBarThickness, range: 1...5, specifier: "%.0f pt")
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Customize Player Buttons").font(.headline).padding([.horizontal, .top])
                    Text("Enable and reorder the buttons that appear in the music player. The first two enabled buttons will appear in the main control bar.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    ReorderableVStack(items: $settings.settings.musicPlayerButtonOrder) { buttonType in PlayerButtonSettingsRow(buttonType: buttonType) }
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 0) {
                    ToggleRow(title: "Enable track info on Hover", description: "Hover over the album art in the live activity to see the song title.", isOn: $settings.settings.enableQuickPeekOnHover)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show track info on Track Change", description: "Briefly show the song title when a new track begins.", isOn: $settings.settings.showQuickPeekOnTrackChange)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show popularity of track in music player", description: "Requires a spotify login", isOn: $settings.settings.showPopularityInMusicPlayer)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Prefer airplay over spotify devices", description: "Default to airplay devices when spotify isn't running and spotify is authenticated", isOn: $settings.settings.preferAirPlayOverSpotify)
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spotify (Private API)").font(.headline).padding([.horizontal, .top])
                    InfoContainer(text: "WARNING: This method uses Spotify’s internal APIs to unlock standard and additional features for both Premium and non-Premium users. Use at your own risk, usage may be subject to Spotify’s Terms of Service.", iconName: "exclamationmark.triangle.fill", color: .yellow).padding(.horizontal)
                    InfoContainer(text: "Sapphire is a Connect controller only, audio always plays on the Spotify desktop app or another speaker.", iconName: "hifispeaker", color: .blue).padding(.horizontal)
                    Divider().padding(.horizontal, 20)
                    if isPrivateAuth {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text("Logged in via Private API")
                                Spacer()
                                Button("Log Out", role: .destructive) { MusicManager.shared.spotifyPrivateAPI.logout() }
                            }.padding()

                            Divider().padding(.leading, 20)

                            ToggleRow(title: "Skip Ads", description: "When Spotify desktop on this Mac plays an ad, relaunch it in the background, then resume via Spotify Connect.", isOn: $settings.settings.skipSpotifyAd)
                            ToggleRow(title: "Show Spotify Tab", description: "When another app is playing, show a Spotify source tab so you can switch medias. Hidden while Spotify itself is the main media source.", isOn: $settings.settings.showSpotifySourceTab)
                                .disabled(!isPrivateAuth)
                            ToggleRow(title: "Live Canvas Video", description: "Show looping Spotify Canvas video behind the artwork when available. Turn off to always use the album thumbnail.", isOn: $settings.settings.spotifyCanvasLiveVideo)
                                .disabled(!isPrivateAuth)
                            ToggleRow(title: "Artist Profile", description: "Show the artist avatar, verified check, and monthly listeners instead of plain artist text.", isOn: $settings.settings.spotifyShowArtistProfile)
                                .disabled(!isPrivateAuth)
                            ToggleRow(title: "Next Song", description: "Show the upcoming track from the queue under the now-playing title during the last 10 seconds of the song.", isOn: $settings.settings.spotifyShowNextSong)
                                .disabled(!isPrivateAuth)
                            ToggleRow(title: "Next Song Album Art", description: "Show album art beside the upcoming track in the live activity.", isOn: $settings.settings.spotifyShowNextSongAlbumArt)
                                .disabled(!isPrivateAuth || !settings.settings.spotifyShowNextSong)
                            ToggleRow(title: "Suggested Songs", description: "Show related song chips you can play from the music player.", isOn: $settings.settings.spotifyShowSuggestedSongs)
                                .disabled(!isPrivateAuth)
                            ToggleRow(title: "Concert Tickets", description: "Show a compact tickets button when nearby concerts are available for the artist.", isOn: $settings.settings.spotifyShowConcertTickets)
                                .disabled(!isPrivateAuth)
                            ToggleRow(title: "Account Badge", description: "Show the Premium / Free account badge next to the track title.", isOn: $settings.settings.spotifyShowAccountBadge)
                                .disabled(!isPrivateAuth)
                        }
                    } else {
                        VStack(spacing: 12) {
                            if let error = privateApiError {
                                Text(error).font(.caption).foregroundColor(.red)
                            }
                            if isPrivateApiLoading {
                                ProgressView().frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Button("Log In via Private API") { handlePrivateApiLogin() }
                                    .buttonStyle(.borderedProminent).tint(.accentColor)
                            }
                        }.padding()
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: isPrivateAuth)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spotify (Official API)").font(.headline).padding([.horizontal, .top])
VStack(alignment: .leading, spacing: 8) {
                        Text("Spotify API Credentials").font(.system(size: 14, weight: .medium))
                        Text("Register your app at developer.spotify.com and copy these values here. The redirect URI is: sapphire://callback").font(.caption).foregroundColor(.secondary).padding(.bottom, 4)
                        Text("Client ID").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        SecureField("Enter your Client ID", text: Binding(
                            get: { APIKeyManager.shared.spotifyClientId },
                            set: { APIKeyManager.shared.spotifyClientId = $0 }
                        )).textFieldStyle(.plain).padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                        Text("Client Secret").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8)).padding(.top, 5)
                        SecureField("Enter your Client Secret", text: Binding(
                            get: { APIKeyManager.shared.spotifyClientSecret },
                            set: { APIKeyManager.shared.spotifyClientSecret = $0 }
                        )).textFieldStyle(.plain).padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                    }.padding().padding(.top, 5)
                    Text("Log in here to enable official features like device switching for Premium users. This is the standard, recommended login method.").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                    Divider().padding(.horizontal, 20)
                    HStack {
                        if isOfficialAuth, let name = officialDisplayName {
                            HStack { Image(systemName: "checkmark.circle.fill").foregroundColor(.green); Text("Logged in as \(name)") }
                            Spacer()
                            Button("Log Out", role: .destructive) { MusicManager.shared.spotifyOfficialAPI.logout() }
                        } else {
                            Text("Not logged in.").foregroundColor(.secondary)
                            Spacer()
                            Button("Log In") { MusicManager.shared.spotifyOfficialAPI.login() }
                        }
                    }.padding()
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: isOfficialAuth)

                VStack(alignment: .leading, spacing: 10) {
                    Text("TIDAL").font(.headline).padding([.horizontal, .top])
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TIDAL API Credentials").font(.system(size: 14, weight: .medium))
                        Text("Create an app at developer.tidal.com, enable the user.read, search.read, collection.read/write, and playlists.read/write scopes, and set the redirect URI exactly to sapphire://callback.").font(.caption).foregroundColor(.secondary).padding(.bottom, 4)
                        Text("Client ID").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        SecureField("Enter your Client ID", text: Binding(
                            get: { APIKeyManager.shared.tidalClientId },
                            set: { APIKeyManager.shared.tidalClientId = $0 }
                        )).textFieldStyle(.plain).padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                        Text("Client Secret").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8)).padding(.top, 5)
                        SecureField("Enter your Client Secret", text: Binding(
                            get: { APIKeyManager.shared.tidalClientSecret },
                            set: { APIKeyManager.shared.tidalClientSecret = $0 }
                        )).textFieldStyle(.plain).padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                    }.padding().padding(.top, 5)
                    Text("Log in here to enable TIDAL features like catalog search and syncing liked tracks and playlists. Requires a TIDAL developer account (third-party access tier).").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                    Divider().padding(.horizontal, 20)
                    HStack {
                        if isTidalAuth, let name = tidalDisplayName {
                            HStack { Image(systemName: "checkmark.circle.fill").foregroundColor(.green); Text("Logged in as \(name)") }
                            Spacer()
                            Button("Log Out", role: .destructive) { MusicManager.shared.tidalAPI.logout() }
                        } else {
                            Text("Not logged in.").foregroundColor(.secondary)
                            Spacer()
                            Button("Log In") { showTidalLogin = true }
                        }
                    }.padding()
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: isTidalAuth)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Lyrics").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Lyrics in Live Activity", description: "Display synchronized lyrics when available.", isOn: $settings.settings.showLyricsInLiveActivity)
                    if settings.settings.showLyricsInLiveActivity {
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Enable Translation", description: "Automatically translate non-English lyrics.", isOn: $settings.settings.enableLyricTranslation)
                        HStack {
                            Text("Translate to"); Spacer()
                            Picker("", selection: $settings.settings.lyricTranslationLanguage) { Text("English").tag("en"); Text("Spanish").tag("es"); Text("French").tag("fr") }.labelsHidden().frame(width: 150)
                        }.padding().disabled(!settings.settings.enableLyricTranslation).opacity(settings.settings.enableLyricTranslation ? 1.0 : 0.5)
                        Divider().padding(.leading, 20)
                        HStack {
                            Text("Lyric Delay"); Spacer()
                            let offset = settings.settings.lyricOffset
                            let label = offset == 0 ? "On time" : String(format: "%+.1fs", offset)
                            if #available(macOS 13.0, *) {
                                Text(NSLocalizedString(label, comment: "Settings label")).font(.caption).foregroundColor(.secondary)
                                Stepper("", value: $settings.settings.lyricOffset, in: -5.0...5.0, step: 0.1)
                                    .labelsHidden()
                            } else {
                                DeferredValueEditor(value: $settings.settings.lyricOffset) { draft, onEditingChanged in
                                    HStack(spacing: 8) {
                                        Slider(
                                            value: draft,
                                            in: -5.0...5.0,
                                            step: 0.1,
                                            label: { Text("Lyric Delay") },
                                            onEditingChanged: onEditingChanged
                                        )
                                        let draftOffset = draft.wrappedValue
                                        let draftLabel = draftOffset == 0 ? "On time" : String(format: "%+.1fs", draftOffset)
                                        Text(draftLabel).font(.caption).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
                                    }
                                }
                            }
                        }.padding()
                        if #available(macOS 26.0, *) {
                            Divider().padding(.leading, 20)
                            ToggleRow(
                                title: "Generate Word-by-Word Timing",
                                description: "When a song only has line timing, listen to the music app's audio on this Mac to time each word, and share good results. Asks for audio access and downloads Apple's speech model once.",
                                isOn: $settings.settings.generateWordTimedLyrics
                            )
                        }
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.showLyricsInLiveActivity)

                if settings.settings.showLyricsInLiveActivity {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Allow Lyrics From:").font(.headline).padding([.horizontal, .top])
                        AppTogglesListView(
                            isEnabled: { app in binding(for: app, isBrowser: app.isBrowser) },
                            maxHeight: 360,
                            browsersSectionTitle: "Browsers (Disabled by Default)"
                        )
                    }.modifier(SettingsContainerModifier()).transition(.opacity.combined(with: .move(edge: .top)))
                }

                RequiredPermissionsView(section: .music)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                syncMusicAuthState()
            }
            .onReceive(MusicManager.shared.$isPrivateAPIAuthenticated) { isPrivateAuth = $0 }
            .onReceive(MusicManager.shared.$isOfficialAPIAuthenticated) { isOfficialAuth = $0 }
            .onReceive(MusicManager.shared.$isTidalAPIAuthenticated) { isTidalAuth = $0 }
            .onReceive(MusicManager.shared.tidalAPI.$userProfile) { profile in
                tidalDisplayName = profile?.username
            }
            .onReceive(MusicManager.shared.spotifyOfficialAPI.$userProfile) { profile in
                officialDisplayName = profile?.displayName
            }
            .onReceive(SpotifyPrivateAPIManager.shared.$loginChallenge) { loginChallenge = $0 }
        }
        .sheet(item: $loginChallenge) { _ in
            SpotifyLoginWebView(
                onComplete: { cookieProperties in
                    MusicManager.shared.spotifyPrivateAPI.completeLoginAfterWebViewSuccess(with: cookieProperties)
                    MusicManager.shared.spotifyPrivateAPI.loginChallenge = nil
                    isPrivateApiLoading = false
                },
                onCancel: {
                    privateApiError = "Login was cancelled."
                    MusicManager.shared.spotifyPrivateAPI.loginChallenge = nil
                    isPrivateApiLoading = false
                }
            )
        }
        .sheet(isPresented: $showTidalLogin) {
            TidalLoginWebView(
                onComplete: { showTidalLogin = false },
                onCancel: { showTidalLogin = false }
            )
        }
    }

    private func syncMusicAuthState() {
        let music = MusicManager.shared
        music.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
        isPrivateAuth = music.isPrivateAPIAuthenticated
        isOfficialAuth = music.isOfficialAPIAuthenticated
        isTidalAuth = music.isTidalAPIAuthenticated
        tidalDisplayName = music.tidalAPI.userProfile?.username
        officialDisplayName = music.spotifyOfficialAPI.userProfile?.displayName
        loginChallenge = music.spotifyPrivateAPI.loginChallenge
    }

    private func handlePrivateApiLogin() {
        isPrivateApiLoading = true
        privateApiError = nil
        MusicManager.shared.spotifyPrivateAPI.login()
    }

    private func binding(for app: SystemApp, isBrowser: Bool) -> Binding<Bool> {
        .init(
            get: { settings.settings.musicAppStates[app.id, default: !isBrowser] },
            set: { settings.settings.musicAppStates[app.id] = $0 }
        )
    }

    private func mediaVisibilityBinding(for app: SystemApp, isBrowser: Bool) -> Binding<Bool> {
        .init(
            get: {
                settings.settings.mediaAppVisibility[app.id]
                    ?? true
            },
            set: { settings.settings.mediaAppVisibility[app.id] = $0 }
        )
    }
}

fileprivate struct MusicLongPressActionPickerRow: View {
    let target: MusicLongPressTarget
    @EnvironmentObject var settings: SettingsEditingSession

    private var selection: Binding<MusicLongPressAction> {
        Binding(
            get: { target.defaultAction(in: settings.settings) },
            set: { settings.settings.setLongPressAction($0, for: target) }
        )
    }

    var body: some View {
        HStack {
            Text("Hold \(target.displayName)")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Picker("", selection: selection) {
                ForEach(target.pickerOptions) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .padding()
    }
}

fileprivate struct PlayerButtonSettingsRow: View {
    let buttonType: MusicPlayerButtonType
    @EnvironmentObject var settings: SettingsEditingSession

    private var isEnabledBinding: Binding<Bool> {
        switch buttonType {
        case .like: return $settings.settings.musicLikeButtonEnabled
        case .shuffle: return $settings.settings.musicShuffleButtonEnabled
        case .repeat: return $settings.settings.musicRepeatButtonEnabled
        case .playlists: return $settings.settings.musicPlaylistsButtonEnabled
        case .devices: return $settings.settings.musicDevicesButtonEnabled
        }
    }

    var body: some View {
        HStack {
            Image(systemName: buttonType.systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30)

            Text(buttonType.displayName)
                .font(.system(size: 14, weight: .medium))

            Spacer()

            SettingsSwitch(isOn: isEnabledBinding)

            ReorderHandle()
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
    }
}

struct WeatherSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Weather")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(spacing: 0) {
                    HStack {
                        Text("Use Celsius")
                        Spacer()
                        Toggle("", isOn: $settings.settings.weatherUseCelsius)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    HStack {
                        Text("Use Metric Units")
                        Spacer()
                        Toggle("", isOn: $settings.settings.weatherUseMetricSystem)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    HStack {
                        Text("Open detailed Weather widget on live activity click")
                        Spacer()
                        Toggle("", isOn: $settings.settings.weatherOpenOnClick)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .weather)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    private var isLastEnabledWidget: Bool {
        settings.settings.calendarWidgetEnabled && settings.settings.enabledWidgetTypes.count <= 1
    }

    private var isAtCapacity: Bool {
        !settings.settings.calendarWidgetEnabled && !WidgetLayoutPolicy.canFit(
            .calendar,
            in: settings.settings.enabledWidgetTypes,
            availableWidth: WidgetLayoutPolicy.availableBarWidth(),
            showDividers: settings.settings.showDividersBetweenWidgets,
            bypassSpaceLimit: settings.settings.bypassWidgetSpaceLimit
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Calendar & Reminders")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Enable Calendar Widget",
                        description: isAtCapacity
                            ? "Not enough notch space on this display."
                            : "Show the calendar widget in the notch widget strip.",
                        isOn: $settings.settings.calendarWidgetEnabled
                    )
                    .disabled(isLastEnabledWidget || isAtCapacity)

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Enable Calendar Live Activity",
                        description: "Show upcoming events as a live activity in the notch.",
                        isOn: $settings.settings.calendarLiveActivityEnabled
                    )
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 0) {
                    HStack {
                        Text("Show All-Day Events")
                        Spacer()
                        Toggle("", isOn: $settings.settings.calendarShowAllDayEvents)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    HStack {
                        Text("Start Week On")
                        Spacer()
                        Picker("", selection: $settings.settings.calendarStartOfWeek) {
                            ForEach(Day.allCases) { day in
                                Text(day.id).tag(day)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    ToggleRow(
                        title: "Open Calendar on Click",
                        description: "Clicking the Calendar live activity will open the expanded calendar view.",
                        isOn: $settings.settings.calendarOpenOnClick
                    )
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .calendar)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
struct EyeBreakRecommendationsView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Eye Health Recommendations")
                    .font(.title2.bold())
                Spacer()
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                LazyVStack(alignment: .center, spacing: 20) {
                    recommendationCard(
                        title: "The 20-20-20 Rule",
                        description: "Every 20 minutes, take a 20-second break to look at something 20 feet away. This helps reduce eye strain and gives eye muscles a break.",
                        icon: "eyes",
                        color: .blue
                    )

                    recommendationCard(
                        title: "Adjust Your Screen",
                        description: "Position your monitor about an arm's length away and adjust the angle of the screen so that the top it is at or slightly below eye level. This reduces strain on your neck and eyes.",
                        icon: "display",
                        color: .green
                    )

                    recommendationCard(
                        title: "Reduce Blue Light",
                        description: "Use Night Shift on your mac to reduce exposure to blue light, especially in dark environments or during late hours when it can interfere with sleep.",
                        icon: "moon.stars.fill",
                        color: .orange
                    )

                    recommendationCard(
                        title: "Optimize Lighting",
                        description: "Ensure your workspace has adequate lighting that doesn't cause glare on your screen. Avoid working in a dark room with just the screen light.",
                        icon: "lightbulb.fill",
                        color: .yellow
                    )

                    recommendationCard(
                        title: "Stay Hydrated",
                        description: "Drink plenty of water throughout the day. Dehydration can contribute to dry eyes and eye strain.",
                        icon: "drop.fill",
                        color: .cyan
                    )
                }
            }

            Button("Got it") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 500, height: 600)
    }

    private func recommendationCard(title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString(title, comment: "Settings title"))
                    .font(.headline)
                Text(NSLocalizedString(description, comment: "Settings description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .frame(minWidth: 400)
        .cornerRadius(12)
    }
}

struct EyeBreakSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var eyeBreakManager = EyeBreakManager.shared
    @State private var showingRecommendationsSheet = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Eye Break")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Enable Eye Break Reminders",
                        description: "Receive live activities reminding you to take breaks.",
                        isOn: $settings.settings.eyeBreakLiveActivityEnabled
                    )
                    .onChange(of: settings.settings.eyeBreakLiveActivityEnabled) {
                        eyeBreakManager.dismissBreak()
                    }
                }
                .modifier(SettingsContainerModifier())

                Group {
                    currentStatusSection
                    configurationSection
                    statisticsSection
                    resetSection
                }
                .disabled(!settings.settings.eyeBreakLiveActivityEnabled)
                .opacity(settings.settings.eyeBreakLiveActivityEnabled ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.2), value: settings.settings.eyeBreakLiveActivityEnabled)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheet(isPresented: $showingRecommendationsSheet) {
                EyeBreakRecommendationsView()
            }
        }
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Eye Break Status")
                    .font(.headline)
                Spacer()

                if eyeBreakManager.isBreakTime {
                    Text("Break in Progress")
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                } else {
                    Text("\(eyeBreakManager.timeUntilNextBreak.asMinuteSecondClock) until next break")
                        .foregroundColor(.secondary)
                }
            }.padding(15)

            if eyeBreakManager.isBreakTime {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Look away from your screen")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text("Focus on an object at least 20 feet away")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: 1 - (eyeBreakManager.timeRemainingInBreak / TimeInterval(settings.settings.eyeBreakBreakDuration)))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .padding(.vertical, 4)

                    HStack {
                        Spacer()

                        Button("Skip") {
                            eyeBreakManager.dismissBreak()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                        Button("Complete Break") {
                            eyeBreakManager.completeBreak()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .center) {
                        Text("\(eyeBreakManager.breaksTakenToday)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Breaks Taken")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    VStack(alignment: .center) {
                        Text("\(eyeBreakManager.currentStreak)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Day Streak")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    VStack(alignment: .center) {
                        Text("\(eyeBreakManager.eyeStrainScore)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(healthColor)
                        Text("Eye Health")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Configuration").font(.headline).padding([.top, .horizontal])

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The 20-20-20 Rule")
                        .font(.subheadline)
                    Text("Every 20 minutes, take a 20-second break to look at something 20 feet away.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Learn More") {
                        showingRecommendationsSheet = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
                Spacer()
                Image(systemName: "eyes")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
            .padding([.horizontal, .top])

            Divider()
                .padding(.horizontal)
                .padding(.vertical, 10)

            CustomSliderRowView(
                label: "Work Interval",
                value: $settings.settings.eyeBreakWorkInterval,
                range: 5...60,
                specifier: "%.0f min",
                onEditingChanged: { isEditing in
                    if !isEditing {
                        eyeBreakManager.dismissBreak()
                    }
                }
            )

            Divider().padding(.leading, 20)

            CustomSliderRowView(
                label: "Break Duration",
                value: $settings.settings.eyeBreakBreakDuration,
                range: 10...60,
                specifier: "%.0f sec",
                onEditingChanged: { isEditing in
                    if !isEditing {
                        eyeBreakManager.dismissBreak()
                    }
                }
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Play Sound Alerts",
                description: "Play sounds when breaks begin and end.",
                isOn: $settings.settings.eyeBreakSoundAlerts
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Show Activity Graph",
                description: "Display a visual graph of your work and break intervals.",
                isOn: $settings.settings.showEyeBreakGraph
            )
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: settings.settings.showEyeBreakGraph)
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Statistics").font(.headline).padding([.top, .horizontal])
            if settings.settings.showEyeBreakGraph {
                EyeBreakGraphView(summaries: eyeBreakManager.dailySummaries)
                    .environmentObject(settings)
                    .padding([.horizontal, .bottom])
                    .transition(.opacity)
            } else {
                Text("Enable the activity graph above to see your eye break statistics.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: settings.settings.showEyeBreakGraph)
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reset & Data").font(.headline).padding([.top, .horizontal])
            Button(action: {
                eyeBreakManager.dismissBreak()
            }) {
                HStack {
                    Text("Reset Timer")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .padding()
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal)

            Button(action: {
                UserDefaults.standard.removeObject(forKey: "EyeBreakHistory")
                eyeBreakManager.dismissBreak()
            }) {
                HStack {
                    Text("Clear All History")
                        .foregroundColor(.red)
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .padding()
            }
            .buttonStyle(.plain)
        }
        .modifier(SettingsContainerModifier())
    }

    private var healthColor: Color {
        let score = eyeBreakManager.eyeStrainScore
        if score > 75 { return .green }
        if score > 50 { return .yellow }
        return .red
    }

}

struct EyeBreakGraphView: View {
    let summaries: [EyeBreakDailySummary]
    @EnvironmentObject var settings: SettingsEditingSession
    @State private var selectedDayName: String?

    private var selectedSummary: EyeBreakDailySummary? {
        chartData.first { $0.dayName == selectedDayName }?.originalSummary
    }

    private struct ChartableBreakData: Identifiable {
        var id: String { dayName }
        let dayName: String
        let completedBreaks: Int
        let missedBreaks: Int
        let originalSummary: EyeBreakDailySummary
    }

    private var chartData: [ChartableBreakData] {
        summaries.map { summary in
            let workIntervalInSeconds = settings.settings.eyeBreakWorkInterval * 60
            let totalIntervals = workIntervalInSeconds > 0 ? Int(summary.workDuration / workIntervalInSeconds) : 0
            let missed = max(0, totalIntervals - summary.completedBreaks)

            return ChartableBreakData(
                dayName: summary.dayName,
                completedBreaks: summary.completedBreaks,
                missedBreaks: missed,
                originalSummary: summary
            )
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            keyMetricsView

            HStack {
                Text("Weekly Eye Break Activity")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 5)

            barChart
                .frame(height: 180)

            dailySummariesView
        }
    }

    private var keyMetricsView: some View {
        HStack(spacing: 12) {
            MetricCardView(
                title: "Today's Breaks",
                value: "\(summaries.first?.completedBreaks ?? 0)",
                icon: "eyes",
                color: .blue,
                trend: "+\(summaries.first?.completedBreaks ?? 0) today"
            )

            MetricCardView(
                title: "Compliance",
                value: "\(Int((summaries.first?.complianceRate ?? 0) * 100))%",
                icon: "checkmark.circle",
                color: complianceColor,
                trend: complianceTrend
            )

            MetricCardView(
                title: "Current Streak",
                value: "\(EyeBreakManager.shared.currentStreak)",
                icon: "bolt",
                color: .orange,
                trend: "days in a row"
            )

            MetricCardView(
                title: "Eye Health",
                value: "\(summaries.first?.eyeStrainScore ?? 100)",
                icon: "heart.text.square",
                color: eyeHealthColor,
                trend: "/100"
            )
        }
    }

    private var barChart: some View {
        Chart(chartData) { dataPoint in
            BarMark(
                x: .value("Day", dataPoint.dayName),
                y: .value("Breaks", dataPoint.completedBreaks)
            )
            .foregroundStyle(by: .value("Type", "Completed"))
            .cornerRadius(6)

            BarMark(
                x: .value("Day", dataPoint.dayName),
                y: .value("Breaks", dataPoint.missedBreaks)
            )
            .foregroundStyle(by: .value("Type", "Missed"))
            .cornerRadius(6)
        }
        .materialChartPlotStyle()
        .chartForegroundStyleScale([
            "Completed": MaterialChartPalette.primary,
            "Missed": MaterialChartPalette.error.opacity(0.65)
        ])
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(MaterialChartPalette.outline)
                AxisValueLabel("\(value.as(Int.self) ?? 0)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(MaterialChartPalette.outline)
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
        .chartXSelection(value: $selectedDayName)
    }

    private var dailySummariesView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Daily Activity")
                .font(.headline)
                .padding(.horizontal, 5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        DailySummaryCard(summary: summary, isSelected: selectedSummary?.id == summary.id)
                            .onTapGesture {
                                selectedDayName = summary.dayName
                            }
                    }
                }
                .padding(10)
                .padding(.horizontal, 0)
            }
        }
    }

    private var complianceColor: Color {
        let rate = summaries.first?.complianceRate ?? 0
        if rate > 0.8 { return .green }
        if rate > 0.5 { return .yellow }
        return .red
    }

    private var complianceTrend: String {
        let current = summaries.first?.complianceRate ?? 0
        let previous = summaries.dropFirst().first?.complianceRate ?? 0

        if current > previous {
            return "↑ Improving"
        } else if current < previous {
            return "↓ Declining"
        }
        return "→ Steady"
    }

    private var eyeHealthColor: Color {
        let score = summaries.first?.eyeStrainScore ?? 100
        if score > 75 { return .green }
        if score > 50 { return .yellow }
        return .red
    }
}

struct MetricCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(NSLocalizedString(title, comment: "Settings title"))
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)

            Text(trend)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct DailySummaryCard: View {
    let summary: EyeBreakDailySummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.dayName)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(healthStatusColor)
                    .frame(width: 10, height: 10)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Work")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(summary.formattedWorkTime)
                        .font(.system(size: 12, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Breaks")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(summary.completedBreaks)")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            HStack {
                Text("Compliance:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                ProgressView(value: summary.complianceRate)
                    .progressViewStyle(LinearProgressViewStyle(tint: healthStatusColor))
                    .frame(width: 60)

                Text("\(Int(summary.complianceRate * 100))%")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(10)
        .frame(width: 200)
        .background(isSelected ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var healthStatusColor: Color {
        let score = summary.eyeStrainScore
        if score > 75 { return .green }
        if score > 50 { return .yellow }
        return .red
    }
}

struct BluetoothSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Bluetooth")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(spacing: 0) {
                    Text("Notifications").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Notify for Low Battery", description: "Show an alert when a connected device's battery is low.", isOn: $settings.settings.bluetoothNotifyLowBattery)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Play Connection Sounds", description: "Play a sound when devices connect or disconnect.", isOn: $settings.settings.bluetoothNotifySound)
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 0) {
                    Text("Live Activity").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Bluetooth Live Activity", description: "Show connection, disconnection, and battery events for Bluetooth devices.", isOn: $settings.settings.bluetoothLiveActivityEnabled)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show Continuity Devices", description: "Show live activity events for Apple devices like iPhone, iPad, Mac, and Apple Watch.", isOn: $settings.settings.showBluetoothContinuityDevices)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show Device Name", description: "Display the device name in the live activity for connection and battery events.", isOn: $settings.settings.showBluetoothDeviceName)
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .bluetooth)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct NeardropSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    @State private var downloadPath: String = ""
    @State private var isPathValid: Bool = true
    @State private var settingsHaveChanged: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 40) {
                // MARK: - Nearby Share Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Nearby Share")
                        .font(.largeTitle.bold())
                        .padding(.bottom)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Enable Nearby Share")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            SettingsSwitch(isOn: $settings.settings.neardropEnabled)
                        }
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))

                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.horizontal, 20)

                        InfoContainer(
                            text: "Nearby Share allows you to share files from Android phones to your Mac using Android's native file sharing (Nearby Share / Quick Share). It's recommended to keep this feature enabled for convenient sharing from family and friends.",
                            iconName: "info.circle.fill",
                            color: .blue
                        )
                        .padding()

                        VStack(alignment: .leading, spacing: 15) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Device Display Name")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)

                                TextField("My Mac", text: $settings.settings.neardropDeviceDisplayName)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.black.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    .foregroundStyle(.white)
                                    .font(.system(size: 13))
                                    .disabled(!settings.settings.neardropEnabled)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Download Location")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)

                                HStack {
                                    TextField("Path", text: $downloadPath, onCommit: validateAndSavePath)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(.white)
                                        .font(.system(size: 13))
                                        .disabled(!settings.settings.neardropEnabled)

                                    Image(systemName: isPathValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(isPathValid ? .green : .red)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPathValid ? Color.white.opacity(0.2) : Color.red, lineWidth: 1))

                                if !isPathValid {
                                    Text("A valid directory is required.")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding([.horizontal, .bottom], 20)
                        .opacity(settings.settings.neardropEnabled ? 1.0 : 0.5)

                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.horizontal, 20)

                        HStack {
                            Text("Open detailed AirDrop widget on live activity click")
                            Spacer()
                            Toggle("", isOn: $settings.settings.neardropOpenOnClick)
                                .labelsHidden().toggleStyle(.switch)
                        }
                        .padding()
                        .disabled(!settings.settings.neardropEnabled)
                        .opacity(settings.settings.neardropEnabled ? 1.0 : 0.5)

                    }
                    .modifier(SettingsContainerModifier())
                    .animation(.easeInOut, value: settings.settings.neardropEnabled)

                    SettingsCard(title: "Swipe Actions", description: "Customize what happens when you swipe a file drop row left or right. Share only applies to File Shelf items.") {

                        SwipeActionPickerRow(
                            title: "Swipe Right",
                            description: "Leading swipe on a file drop row.",
                            selection: $settings.settings.swipeActionSettings.fileDropLeading,
                            options: FileDropSwipeAction.allCases,
                            label: { $0.displayName }
                        )

                        Divider().padding(.leading, 20)

                        SwipeActionPickerRow(
                            title: "Swipe Left",
                            description: "Trailing swipe on a file drop row.",
                            selection: $settings.settings.swipeActionSettings.fileDropTrailing,
                            options: FileDropSwipeAction.allCases,
                            label: { $0.displayName }
                        )
                    }
                }
                OpenBubblesActivationView()

            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                self.downloadPath = settings.settings.neardropDownloadLocationPath
            }
            .onChange(of: downloadPath) { _, newValue in
                self.isPathValid = validate(path: newValue)
            }
            .onChange(of: settings.settings.neardropEnabled) {
                settingsHaveChanged = true
            }
            .onChange(of: settings.settings.neardropDeviceDisplayName) {
                settingsHaveChanged = true
            }
            .animation(.spring(), value: settingsHaveChanged)

            RequiredPermissionsView(section: .neardrop)
        }
    }

    private func validateAndSavePath() {
        if validate(path: downloadPath) {
            settings.settings.neardropDownloadLocationPath = downloadPath
        }
    }

    private func validate(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

struct AboutSettingsView: View {
    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    @EnvironmentObject var settingsModel: SettingsEditingSession
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @ObservedObject private var debugMode = DebugMode.shared
    @State private var isExportingSettings = false
    @State private var isImportingSettings = false
    @State private var backupDocument = SettingsBackupDocument(settings: Settings())
    @State private var backupStatusMessage: BackupStatusMessage?
    @State private var showingResetConfirmation = false
    @State private var debugTapCount = 0
    @State private var debugTapResetTask: Task<Void, Never>?

    private var displayedReleaseChannel: ReleaseChannel {
        ReleaseChannelPolicy.displayedChannel(for: settingsModel.settings)
    }

    private var releaseChannelBinding: Binding<ReleaseChannel> {
        Binding(
            get: { displayedReleaseChannel },
            set: { newValue in
                guard SubscriptionAccess.hasAccess(to: .betaSoftwareUpdates) || newValue == .stable else { return }
                settingsModel.settings.releaseChannel = newValue
            }
        )
    }

    private var versionLabel: String {
        if BetaEntitlementRuntime.isBetaBuild {
            return "Version \(currentAppVersion) Beta"
        }
        return "Version \(currentAppVersion)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("About").font(.largeTitle.bold()).padding(.bottom)

                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if debugMode.isEnabled {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Circle().fill(Color.orange))
                                    .offset(x: 6, y: 6)
                            }
                        }
                        .padding(.trailing, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { handleDebugIconTap() }
                        .help(debugMode.isEnabled ? "Debug mode is ON — tap 5× quickly to disable" : "Tap 5× quickly to enable debug mode")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sapphire").font(.largeTitle.weight(.bold))
                        Text(versionLabel).foregroundStyle(.secondary).textSelection(.enabled)

                        if debugMode.isEnabled {
                            Label("Debug Mode Enabled", systemImage: "hammer.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 10) {
                            Link(destination: URL(string: "https://sapphire-app.tech/")!) {
                                Image(systemName: "link")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Link(destination: URL(string: "https://github.com/cshariq/Sapphire")!) {
                                Image("github_logo")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Link(destination: URL(string: "https://discord.gg/TdRjC2kNnU")!) {
                                Image("discord_logo")
                                    .resizable()
                                        .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .padding(6)
                                    .background(Color(red: 0.35, green: 0.40, blue: 0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 6)
                    }
                    Spacer()
                }

                sapphireUpdatesPane

                settingsBackupPane

                VStack(alignment: .leading, spacing: 0) {
                    Text("Permissions Overview").font(.headline).padding([.horizontal, .top])
                    ForEach(permissionsManager.allPermissions) { permission in
                        PermissionStatusRowView(permission: permission)
                        if permission.id != permissionsManager.allPermissions.last?.id { Divider().padding(.leading, 60) }
                    }
                }.modifier(SettingsContainerModifier()).onAppear(perform: permissionsManager.checkAllPermissions)

                Text("© 2025 Shariq Charolia. All rights reserved.").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center).padding(.top, 20)
            }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                ReleaseChannelPolicy.reconcileStoredPreference(&settingsModel.settings)
                settingsModel.commitNow()
                updateChecker.checkForUpdatesMatchingCurrentChannel()
            }
        }
        .onChange(of: settingsModel.settings.releaseChannel) { _, _ in
            settingsModel.commitNow()
            updateChecker.checkForUpdatesMatchingCurrentChannel()
        }
        .onChange(of: settingsModel.settings.automaticUpdateChecksEnabled) { _, enabled in
            settingsModel.commitNow()
            updateChecker.setAutomaticChecksEnabled(enabled)
        }
        .onChange(of: settingsModel.settings.updateAvailableNotificationsEnabled) { _, enabled in
            if enabled { updateChecker.requestNotificationAuthorization() }
        }
        .onChange(of: settingsModel.settings.automaticallyDownloadSapphireUpdates) { _, enabled in
            guard enabled,
                  settingsModel.settings.automaticUpdateChecksEnabled,
                  case .available(_, let asset) = updateChecker.status else { return }
            updateChecker.downloadUpdate(asset: asset)
        }
        .fileExporter(
            isPresented: $isExportingSettings,
            document: backupDocument,
            contentType: .sapphireSettingsBackup,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                backupStatusMessage = BackupStatusMessage(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    message: "Settings backup exported successfully."
                )
            case .failure(let error):
                backupStatusMessage = BackupStatusMessage(
                    icon: "xmark.octagon.fill",
                    color: .red,
                    message: "Export failed: \(error.localizedDescription)"
                )
            }
        }
        .fileImporter(
            isPresented: $isImportingSettings,
            allowedContentTypes: [.sapphireSettingsBackup, .json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try settingsModel.importSettings(from: url)
                    backupStatusMessage = BackupStatusMessage(
                        icon: "arrow.down.doc.fill",
                        color: .green,
                        message: "Imported settings from \(url.lastPathComponent)."
                    )
                } catch {
                    backupStatusMessage = BackupStatusMessage(
                        icon: "xmark.octagon.fill",
                        color: .red,
                        message: "Import failed: \(error.localizedDescription)"
                    )
                }
            case .failure(let error):
                backupStatusMessage = BackupStatusMessage(
                    icon: "xmark.octagon.fill",
                    color: .red,
                    message: "Import failed: \(error.localizedDescription)"
                )
            }
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                settingsModel.resetAllSettings()
                backupStatusMessage = BackupStatusMessage(
                    icon: "arrow.counterclockwise.circle.fill",
                    color: .orange,
                    message: "All Sapphire settings were reset to defaults."
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current preferences across the app.")
        }
    }

    private var settingsBackupPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconBadge(systemImage: "externaldrive.badge.timemachine", color: .blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings Backup")
                        .font(.headline)
                    Text("Save a portable copy of your Sapphire preferences or restore one you exported earlier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding()

            HStack(spacing: 10) {
                Button {
                    backupDocument = settingsModel.makeBackupDocument()
                    isExportingSettings = true
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    isImportingSettings = true
                } label: {
                    Label("Restore Backup", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom)

            if let backupStatusMessage {
                HStack(spacing: 8) {
                    Image(systemName: backupStatusMessage.icon)
                        .foregroundStyle(backupStatusMessage.color)
                    Text(backupStatusMessage.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(backupStatusMessage.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
                .padding(.bottom)
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Fresh")
                        .font(.subheadline.weight(.medium))
                    Text("Restore all Sapphire preferences to their defaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Settings", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
        }
        .modifier(SettingsContainerModifier())
    }

    private var sapphireUpdatesPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModernUpdateStatusView(updateChecker: updateChecker)

            if let error = updateChecker.lastCheckError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Release Channel")
                    .font(.headline)
                    .padding([.horizontal, .top])
                Text("Choose which update channel to receive releases from.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                ModernChannelSwitcher(
                    selection: releaseChannelBinding,
                    hasBetaAccess: SubscriptionAccess.hasAccess(to: .betaSoftwareUpdates),
                    isLockedToRunningBuild: false
                )
                .padding(.horizontal)
                .padding(.bottom)

                if BetaEntitlementRuntime.isBetaBuild && settingsModel.settings.releaseChannel == .stable {
                    Text("You're on a beta build. Switching to Stable lets you install the latest stable release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                } else if !SubscriptionAccess.hasAccess(to: .betaSoftwareUpdates) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.caption2)
                        Text("Beta access requires a Plus subscription or higher.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
            .modifier(SettingsContainerModifier())

            VStack(alignment: .leading, spacing: 0) {
                Text("Update Preferences")
                    .font(.headline)
                    .padding([.horizontal, .top])
                ToggleRow(
                    title: "Automatic update checks",
                    description: "Check after launch, wake, network recovery, and on a recurring schedule.",
                    isOn: $settingsModel.settings.automaticUpdateChecksEnabled
                )
                Divider().padding(.leading)
                ToggleRow(
                    title: "Download verified updates automatically",
                    description: "Download in the background. Installation always waits for you.",
                    isOn: $settingsModel.settings.automaticallyDownloadSapphireUpdates
                )
                .disabled(!settingsModel.settings.automaticUpdateChecksEnabled)
                .opacity(settingsModel.settings.automaticUpdateChecksEnabled ? 1 : 0.5)
                Divider().padding(.leading)
                ToggleRow(
                    title: "Update notifications",
                    description: "Notify you when a verified Sapphire release is ready.",
                    isOn: $settingsModel.settings.updateAvailableNotificationsEnabled
                )
                .disabled(!settingsModel.settings.automaticUpdateChecksEnabled)
                .opacity(settingsModel.settings.automaticUpdateChecksEnabled ? 1 : 0.5)
                Divider().padding(.leading)
                ToggleRow(
                    title: "Show update Live Activity",
                    description: "Show an alert in the notch when a new Sapphire version is available.",
                    isOn: $settingsModel.settings.showUpdateAvailableLiveActivity
                )
            }
            .modifier(SettingsContainerModifier())
        }
    }

    var currentAppVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }

    private func handleDebugIconTap() {
        debugTapCount += 1
        debugTapResetTask?.cancel()
        debugTapResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled {
                await MainActor.run { debugTapCount = 0 }
            }
        }

        if debugTapCount >= DebugMode.requiredTapCount {
            debugTapCount = 0
            debugTapResetTask?.cancel()
            debugTapResetTask = nil
            debugMode.isEnabled.toggle()
        }
    }

    private var backupFilename: String {
        "Sapphire-Settings-\(Self.backupDateFormatter.string(from: .now))"
    }
}

private struct BackupStatusMessage: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let message: String
}

struct ModernUpdateStatusView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @State private var upToDateAnimationTrigger = false
    @State private var showingReleaseNotes = false

    private var canShowReleaseNotes: Bool {
        switch updateChecker.status {
        case .upToDate, .available, .downloading, .downloaded:
            return updateChecker.releaseNotes != nil || updateChecker.releaseNotesURL != nil
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            switch updateChecker.status {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for Updates...").foregroundStyle(.secondary)
                }
            case .upToDate:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: upToDateAnimationTrigger)
                    Text("You are up to date!")
                        .foregroundStyle(.secondary)
                    if canShowReleaseNotes {
                        releaseNotesButton
                    }
                    checkForUpdatesButton
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .onAppear {
                    upToDateAnimationTrigger.toggle()
                }
            case .available(let version, let asset):
                VStack(spacing: 12) {
                    Text("Version \(version) is available!")
                        .font(.system(size: 16, weight: .bold))

                    Button(action: { updateChecker.downloadUpdate(asset: asset) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Update")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.gradient)
                        .clipShape(Capsule())
                        .shadow(color: .accentColor.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)

                    if canShowReleaseNotes {
                        releaseNotesButton
                    }
                    Button("Check Again") {
                        updateChecker.checkForUpdatesMatchingCurrentChannel()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .downloading(let progress):
                VStack(spacing: 12) {
                    DownloadingView(progress: progress, onCancel: {
                        updateChecker.cancelDownload()
                    })
                    if canShowReleaseNotes {
                        releaseNotesButton
                    }
                }
                .transition(.opacity)
            case .downloaded:
                VStack(spacing: 12) {
                    Text("Download Complete!")
                        .font(.system(size: 16, weight: .bold))
                    Button(action: { updateChecker.installAndRelaunch() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Install and Relaunch")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green.gradient)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)

                    if canShowReleaseNotes {
                        releaseNotesButton
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing... App will relaunch.").foregroundStyle(.secondary)
                }
            case .error(let message):
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                        Text(message).foregroundStyle(.secondary).lineLimit(1)
                    }
                    checkForUpdatesButton
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .modifier(SettingsContainerModifier())
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: updateChecker.status)
        .sheet(isPresented: $showingReleaseNotes) {
            ReleaseNotesSheet(
                version: updateChecker.releaseNotesVersion ?? currentAppVersion,
                notes: updateChecker.releaseNotes,
                url: updateChecker.releaseNotesURL
            )
        }
    }

    private var checkForUpdatesButton: some View {
        Button("Check for Updates") {
            updateChecker.checkForUpdatesMatchingCurrentChannel()
        }
    }

    private var releaseNotesButton: some View {
        Button {
            showingReleaseNotes = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text("Release Notes")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct ReleaseNotesSheet: View {
    let version: String
    let notes: String?
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    private var attributedNotes: AttributedString? {
        guard let notes else { return nil }
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return try? AttributedString(markdown: notes, options: options)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Release Notes")
                        .font(.headline)
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let url {
                    Link(destination: url) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.medium))
                    }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                Group {
                    if let attributedNotes {
                        Text(attributedNotes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else if let notes, !notes.isEmpty {
                        Text(notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        VStack(spacing: 10) {
                            Text("No release notes were included for this version.")
                                .foregroundStyle(.secondary)
                            if let url {
                                Link("View on GitHub", destination: url)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 480)
    }
}

struct DownloadingView: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Downloading Update...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: 12)
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: (300 * progress), height: 12)
                    .animation(.easeOut, value: progress)
            }
            .frame(width: 300)

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModernChannelSwitcher: View {
    @Binding var selection: ReleaseChannel
    let hasBetaAccess: Bool
    var isLockedToRunningBuild: Bool = false
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReleaseChannel.allCases, id: \.self) { channel in
                Text(channel == .stable ? "Stable" : "Beta")
                    .font(.subheadline.weight(selection == channel ? .semibold : .regular))
                    .foregroundStyle(selection == channel ? .white : .secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if selection == channel {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "channelPill", in: namespace)
                            }
                        }
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard !isLockedToRunningBuild else { return }
                        guard hasBetaAccess || channel == .stable else { return }
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                            selection = channel
                        }
                    }
                    .opacity(isLockedToRunningBuild && channel != selection ? 0.35 : ((channel == .beta && !hasBetaAccess) ? 0.4 : 1))
            }
        }
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .opacity(isLockedToRunningBuild ? 0.85 : 1)
    }
}

fileprivate struct NotchButtonRowView: View {
    let buttonType: NotchButtonType

    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    private var isEnabledBinding: Binding<Bool> {
        switch buttonType {
        case .settings, .spacer:
            return .constant(true)
        case .fileShelf: return $settings.settings.fileShelfIconEnabled
        case .notes: return $settings.settings.notesIconEnabled
        case .clipboard: return $settings.settings.clipboardIconEnabled
        case .intelligenceLive, .intelligence:
            return Binding(
                get: {
                    settings.settings.intelligenceEnabled
                        && permissionsManager.areIntelligencePermissionsGranted
                },
                set: { newValue in
                    guard permissionsManager.areIntelligencePermissionsGranted else {
                        settings.settings.intelligenceEnabled = false
                        return
                    }
                    settings.settings.intelligenceEnabled = newValue
                }
            )
        case .focusSession: return $settings.settings.focusSessionIconEnabled
        case .caffeine: return $settings.settings.caffeinateEnabled
        case .battery: return $settings.settings.batteryEstimatorEnabled
        case .multiAudio: return $settings.settings.showMultiAudioIcon
        case .pin: return $settings.settings.pinEnabled
        }
    }

    private var isToggleDisabled: Bool {
        switch buttonType {
        case .settings, .spacer:
            return true
        case .intelligenceLive, .intelligence:
            return !permissionsManager.areIntelligencePermissionsGranted
        case .focusSession:
            return false
        default:
            return false
        }
    }

    var body: some View {
        HStack {
            if buttonType == .spacer {
                HStack {
                    Rectangle().fill(.secondary).frame(height: 1)
                    Text("Center Spacer")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Rectangle().fill(.secondary).frame(height: 1)
                }
            } else {
                Image(systemName: buttonType.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30)

                Text(buttonType.displayName)
                    .font(.system(size: 14, weight: .medium))
            }

            Spacer()

            SettingsSwitch(isOn: isEnabledBinding)
                .disabled(isToggleDisabled)
                .opacity(isToggleDisabled ? 0 : 1)

            ReorderHandle()
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 40) {
                Text("Appearance")
                    .font(.largeTitle.bold())
                PerDisplayNotchSettingsView()
                NotchAppearanceEditorView(appearance: $settings.settings.notchWidgetAppearance, title: "Expanded Notch Appearance")
                NotchAppearanceEditorView(appearance: $settings.settings.notchLiveActivityAppearance, title: "Collapsed Notch Appearance")
                MenuBarHidingSettingsView()
                MenuBarProfilesSettingsView()
                MenuBarAppearanceSettingsView()
                MenuBarSpacingSettingsView()
                RequiredPermissionsView(section: .appearance)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct PerDisplayNotchSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    private var connectedScreens: [NSScreen] {
        NSScreen.screens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Per-Display Overrides").font(.title2.bold())
                Text("Customize notch size and inactive-hiding for each display individually. Changes here override the global settings for the selected display.").font(.caption).foregroundColor(.secondary)
            }

            if connectedScreens.isEmpty {
                Text("No displays detected.")
                    .foregroundColor(.secondary)
                    .padding()
                    .modifier(SettingsContainerModifier())
            } else {
                VStack(spacing: 0) {
                    ForEach(connectedScreens, id: \.displayIdentifier) { screen in
                        perDisplayRow(for: screen)
                        if screen.displayIdentifier != connectedScreens.last?.displayIdentifier {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .modifier(SettingsContainerModifier())
            }
        }
    }

    @ViewBuilder
    private func perDisplayRow(for screen: NSScreen) -> some View {
        let displayID = screen.displayIdentifier
        let isBuiltIn = CGDisplayIsBuiltin(screen.displayID) != 0
        let hasOverride = settings.settings.perDisplayNotchSize[displayID] != nil
        let resolvedConfig = ResolvedNotchConfiguration(from: settings.settings, screen: screen)
        let actualWidth = resolvedConfig.universalWidth
        let actualHeight = resolvedConfig.universalHeight
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundColor(.secondary)
                Text(screen.displayLabel)
                    .font(.headline)
                if isBuiltIn { Text("Built-in").font(.caption).foregroundColor(.secondary) }
                Spacer()
            }

            HStack(spacing: 18) {
                sizeControl(
                    label: "Width",
                    value: perDisplayWidthBinding(displayID: displayID, defaultValue: actualWidth),
                    range: 80...400,
                    hasOverride: hasOverride
                )
                sizeControl(
                    label: "Height",
                    value: perDisplayHeightBinding(displayID: displayID, defaultValue: actualHeight),
                    range: 10...80,
                    hasOverride: hasOverride
                )
                Button {
                    settings.settings.perDisplayNotchSize.removeValue(forKey: displayID)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(!hasOverride)
                .help("Clear per-display size override; revert to automatic size")
            }

            Toggle("Hide notch when inactive (this display)", isOn: perDisplayInactiveBinding(for: displayID))
                .font(.callout)
        }
        .padding()
    }

    private func perDisplayWidthBinding(displayID: String, defaultValue: CGFloat) -> Binding<Double> {
        Binding<Double>(
            get: {
                if let override = settings.settings.perDisplayNotchSize[displayID], override.width > 0 {
                    return Double(override.width)
                }
                return Double(defaultValue)
            },
            set: { newValue in
                var override = settings.settings.perDisplayNotchSize[displayID] ?? NotchSizeOverride()
                override.width = CGFloat(newValue)
                settings.settings.perDisplayNotchSize[displayID] = override
            }
        )
    }

    private func perDisplayHeightBinding(displayID: String, defaultValue: CGFloat) -> Binding<Double> {
        Binding<Double>(
            get: {
                if let override = settings.settings.perDisplayNotchSize[displayID], override.height > 0 {
                    return Double(override.height)
                }
                return Double(defaultValue)
            },
            set: { newValue in
                var override = settings.settings.perDisplayNotchSize[displayID] ?? NotchSizeOverride()
                override.height = CGFloat(newValue)
                settings.settings.perDisplayNotchSize[displayID] = override
            }
        )
    }

    private func sizeControl(label: String, value: Binding<Double>, range: ClosedRange<Double>, hasOverride: Bool) -> some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString(label, comment: "Settings label"))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 62)
                .multilineTextAlignment(.trailing)
            VStack(spacing: 0) {
                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 9)
                }
                .buttonStyle(.plain)
                .help("Increase \(label)")

                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 9)
                }
                .buttonStyle(.plain)
                .help("Decrease \(label)")
            }
            Text("pt")
                .font(.caption)
                .foregroundColor(.secondary)
            if !hasOverride {
                Text("auto")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .help("Automatic size; editing creates a per-display override")
            }
        }
    }

    private func perDisplayInactiveBinding(for displayID: String) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                settings.settings.perDisplayHideNotchWhenInactive[displayID]
                    ?? settings.settings.hideNotchWhenInactive
            },
            set: { newValue in
                settings.settings.perDisplayHideNotchWhenInactive[displayID] = newValue
            }
        )
    }
}

struct MenuBarHidingSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Icon Hiding").font(.title2.bold())
                Text("Hide and show menu bar items using an expandable section.").font(.caption).foregroundColor(.secondary)
            }

            VStack(spacing: 0) {
                ToggleRow(title: "Enable Menu Bar Icon Hiding", description: "", isOn: $settings.settings.menuBarEnabled)
            }.modifier(SettingsContainerModifier())

            if settings.settings.menuBarEnabled {
                VStack(alignment: .leading, spacing: 0) {

                    Text("Control Item Icons").font(.headline).padding([.top, .horizontal])
                    Text("Choose the icon style for the main control item.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 10)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ControlItemIconStyle.allCases) { iconStyle in
                                ControlItemIconPreview(iconStyle: iconStyle, isSelected: settings.settings.controlItemIconStyle == iconStyle) {
                                    withAnimation { settings.settings.controlItemIconStyle = iconStyle }
                                }
                            }
                        }.padding(.horizontal).padding(.bottom, 12)
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    InfoContainer(text: "To customize the shown icons, right click on the menu bar and select 'Edit Menu Bar Items'. The icons placed in between the dot and expansion icon will always be shown, the icons placed in between the two dots will be hidden when the menu is collapsed, and the icons after the dot will always be hidden.", iconName: "info.circle", color: Color.mint).padding()

                    Image("MenubarDemo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480)
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    Text("Show Hidden Items").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show on Click", description: "Show hidden items when clicking empty menu bar space", isOn: $settings.settings.showOnClick)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show on Hover", description: "Show hidden items after hovering over the menu bar", isOn: $settings.settings.showOnHover)
                    if settings.settings.showOnHover {
                        CustomSliderRowView(
                            label: "Hover Delay",
                            value: $settings.settings.showOnHoverDelay,
                            range: 0.1...1.0,
                            specifier: "%.2fs"
                        )
                        .padding(.horizontal, 60)
                        .padding(.bottom, 8)
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Auto-Rehide").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Automatically Rehide Items", description: "Automatically hide items after they're shown", isOn: $settings.settings.autoRehide)
                    if settings.settings.autoRehide {
                        Divider().padding(.leading, 20)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rehide Strategy").font(.subheadline).foregroundColor(.secondary)
                            Picker("", selection: $settings.settings.rehideStrategy) {
                                Text("Smart (when mouse leaves)").tag("smart"); Text("Timed").tag("timed")
                            }.pickerStyle(.segmented).padding(.horizontal)
                        }.padding()
                        if settings.settings.rehideStrategy == "timed" {
                            CustomSliderRowView(label: "Hide After", value: $settings.settings.tempShowInterval, range: 1.0...30.0, specifier: "%.1fs")
                        }
                    }
                }.modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.autoRehide || settings.settings.rehideStrategy == "timed")

                VStack(alignment: .leading, spacing: 0) {
                    Text("Hiding Appearance").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Section Dividers", description: "", isOn: $settings.settings.showSectionDividers)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Enable Always-Hidden Section", description: "", isOn: $settings.settings.enableAlwaysHiddenSection)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Hide Main Control Icon", description: "", isOn: $settings.settings.hideMenuBarIcon)
                }.modifier(SettingsContainerModifier())
            }
        }
        .animation(.easeInOut, value: settings.settings.menuBarEnabled)
    }
}

// MARK: - Menu Bar Profiles (Conditional Reveal + Display/Space/Focus Bindings)

struct MenuBarProfilesSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Profiles").font(.title2.bold())
                Text("Reveal hidden menu bar items when a condition is met — battery level, active Focus, Wi-Fi network, or a script's exit code — and bind profiles to displays, Spaces, or Focus filters.").font(.caption).foregroundColor(.secondary)
            }

            VStack(spacing: 0) {
                PremiumFeatureView(feature: .menuBarProfiles) {
                    ToggleRow(
                        title: "Enable Menu Bar Profiles",
                        description: "Evaluate profile conditions in the background to reveal hidden items automatically",
                        isOn: $settings.settings.menuBarProfilesEnabled
                    )
                }
            }.modifier(SettingsContainerModifier())

            if settings.settings.menuBarProfilesEnabled {
                MenuBarProfileEditorView()
                    .premiumFeature(.menuBarProfiles)
            }
        }
        .animation(.easeInOut, value: settings.settings.menuBarProfilesEnabled)
    }
}

private struct MenuBarProfileEditorView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @State private var expandedProfileIDs: Set<UUID> = []

    private var profilesBinding: Binding<[MenuBarProfile]> {
        $settings.settings.menuBarProfiles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Profiles").font(.headline)
                Spacer()
                Button {
                    let newProfile = MenuBarProfile(name: "Profile \(settings.settings.menuBarProfiles.count + 1)")
                    _ = withAnimation(.easeInOut(duration: 0.2)) { expandedProfileIDs.insert(newProfile.id) }
                    settings.settings.menuBarProfiles.append(newProfile)
                } label: {
                    Label("Add Profile", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
            }

            if settings.settings.menuBarProfiles.isEmpty {
                InfoContainer(
                    text: "Create a profile, add reveal conditions, and optionally bind it to a display, a Space, or a Focus filter. When a bound context is active and any condition is met, hidden items are revealed.",
                    iconName: "info.circle",
                    color: .mint
                ).padding()
                .modifier(SettingsContainerModifier())
            } else {
                VStack(spacing: 12) {
                    ForEach(profilesBinding) { $profile in
                        MenuBarProfileCardView(profile: $profile, isExpanded: expandedProfileIDs.contains(profile.id)) { changed in
                            if changed {
                                expandedProfileIDs.insert(profile.id)
                            } else {
                                expandedProfileIDs.remove(profile.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MenuBarProfileCardView: View {
    @Binding var profile: MenuBarProfile
    let isExpanded: Bool
    var onExpandedChange: (Bool) -> Void = { _ in }
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: profile.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                TextField("Profile name", text: $profile.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text(profile.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                SettingsSwitch(isOn: $profile.isEnabled)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { onExpandedChange(!isExpanded) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    settings.settings.menuBarProfiles.removeAll { $0.id == profile.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider()

                MenuBarRevealConditionsSection(profile: $profile)

                Divider()

                MenuBarProfileBindingsSection(profile: $profile)
            }
        }
        .padding()
        .modifier(SettingsContainerModifier())
    }
}

// MARK: - Reveal Conditions

private struct MenuBarRevealConditionsSection: View {
    @Binding var profile: MenuBarProfile
    @State private var focusOptions: [MenuBarProfileEngine.FocusModeOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reveal When").font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(MenuBarRevealConditionKind.allCases) { kind in
                        Button {
                            profile.revealConditions.append(MenuBarRevealCondition(kind: kind))
                        } label: {
                            Label(kind.displayName, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Label("Add Condition", systemImage: "plus.circle")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if profile.revealConditions.isEmpty {
                Text("No conditions — this profile will never reveal items.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach($profile.revealConditions) { $condition in
                    HStack(spacing: 10) {
                        Image(systemName: condition.kind.systemImage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        MenuBarRevealConditionEditor(condition: $condition, focusOptions: focusOptions)

                        Button {
                            let doomed = condition.id
                            DispatchQueue.main.async {
                                profile.revealConditions.removeAll { $0.id == doomed }
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { refreshFocusOptions() }
    }

    private func refreshFocusOptions() {
        Task.detached(priority: .utility) {
            let options = MenuBarProfileEngine.fetchAvailableFocusModes()
            await MainActor.run { self.focusOptions = options }
        }
    }
}

private struct MenuBarRevealConditionEditor: View {
    @Binding var condition: MenuBarRevealCondition
    let focusOptions: [MenuBarProfileEngine.FocusModeOption]

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.kind) {
                ForEach(MenuBarRevealConditionKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 210)

            switch condition.kind {
            case .batteryBelow, .batteryAbove:
                HStack(spacing: 4) {
                    TextField("Level", value: $condition.batteryThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .charging:
                Text("while plugged in")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .onBatteryPower:
                Text("while unplugged")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .focusActive:
                Text("any Focus mode")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .focusIdentifier:
                Picker("", selection: $condition.focusIdentifier) {
                    Text("Choose Focus…").tag("")
                    ForEach(focusOptions) { option in
                        Label(option.name, systemImage: option.symbolName).tag(option.identifier)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)

            case .wifiEquals:
                TextField("Wi-Fi network name", text: $condition.wifiNetworkName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)

            case .wifiConnected:
                Text("any network")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .scriptSucceeds, .scriptFails, .scriptExitCode:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("/path/to/script.sh", text: $condition.scriptPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        if condition.kind == .scriptExitCode {
                            Text("exit =")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("0", value: $condition.scriptExitCode, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 44)
                        }
                    }
                    HStack(spacing: 6) {
                        TextField("optional argument", text: $condition.scriptArgument)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Text("re-checked every")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("30", value: $condition.scriptPollInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                        Text("sec")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Profile Bindings

private struct MenuBarProfileBindingsSection: View {
    @Binding var profile: MenuBarProfile
    @EnvironmentObject var settings: SettingsEditingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bind To").font(.subheadline.weight(.semibold))

            ToggleRow(
                title: "Displays",
                description: "Apply this profile only on the selected displays",
                isOn: $profile.bindsToDisplays
            )
            if profile.bindsToDisplays {
                MenuBarDisplayBindingsEditor(profile: $profile)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            ToggleRow(
                title: "Spaces",
                description: "Apply this profile only on the selected desktop Spaces (numbered like the Space switcher)",
                isOn: $profile.bindsToSpaces
            )
            if profile.bindsToSpaces {
                MenuBarSpaceBindingsEditor(profile: $profile)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            ToggleRow(
                title: "Focus",
                description: "Apply this profile only while the selected Focus filters are active",
                isOn: $profile.bindsToFocus
            )
            if profile.bindsToFocus {
                MenuBarFocusBindingsEditor(profile: $profile)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct MenuBarDisplayBindingsEditor: View {
    @Binding var profile: MenuBarProfile

    private var connectedScreens: [NSScreen] { NSScreen.screens }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $profile.displayScope) {
                Text("All displays").tag(MenuBarProfileDisplayScope.allDisplays)
                Text("Selected displays").tag(MenuBarProfileDisplayScope.selectedDisplays)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if profile.displayScope == .selectedDisplays {
                if connectedScreens.isEmpty {
                    Text("No displays detected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(connectedScreens, id: \.displayIdentifier) { screen in
                            let id = screen.displayIdentifier
                            let isBound = profile.displayBindings.contains { $0.displayIdentifier == id }
                            Button {
                                if isBound {
                                    profile.displayBindings.removeAll { $0.displayIdentifier == id }
                                } else {
                                    profile.displayBindings.append(MenuBarDisplayBinding(displayIdentifier: id, displayLabel: screen.displayLabel))
                                }
                            } label: {
                                HStack {
                                    Image(systemName: isBound ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isBound ? Color.accentColor : Color.secondary)
                                    Image(systemName: CGDisplayIsBuiltin(screen.displayID) != 0 ? "laptopcomputer" : "display")
                                    Text(screen.displayLabel)
                                        .font(.callout)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct MenuBarSpaceBindingsEditor: View {
    @Binding var profile: MenuBarProfile
    @State private var availableSpaces: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spaces to activate this profile on:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...max(1, availableSpaces), id: \.self) { number in
                        let isBound = profile.spaceNumbers.contains(number)
                        Button {
                            if isBound {
                                profile.spaceNumbers.removeAll { $0 == number }
                            } else {
                                profile.spaceNumbers.append(number)
                                profile.spaceNumbers.sort()
                            }
                        } label: {
                            Text("\(number)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 32, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isBound ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(isBound ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("Detected Spaces: \(availableSpaces)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("Add space", onIncrement: { availableSpaces += 1 }, onDecrement: { availableSpaces = max(1, availableSpaces - 1) })
                    .font(.caption)
            }
        }
    }
}

private struct MenuBarFocusBindingsEditor: View {
    @Binding var profile: MenuBarProfile
    @State private var focusOptions: [MenuBarProfileEngine.FocusModeOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if focusOptions.isEmpty {
                Text("No Focus modes found (or unavailable without Focus permission).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(focusOptions) { option in
                        let isBound = profile.focusIdentifiers.contains(option.identifier)
                        Button {
                            if isBound {
                                profile.focusIdentifiers.removeAll { $0 == option.identifier }
                            } else {
                                profile.focusIdentifiers.append(option.identifier)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isBound ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isBound ? Color.accentColor : Color.secondary)
                                Image(systemName: option.symbolName)
                                    .font(.callout)
                                Text(option.name)
                                    .font(.callout)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Leave empty selections unchecked to bind to any Focus filter by enabling \"Focus\" alone.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear { refreshFocusOptions() }
    }

    private func refreshFocusOptions() {
        Task.detached(priority: .utility) {
            let options = MenuBarProfileEngine.fetchAvailableFocusModes()
            await MainActor.run { self.focusOptions = options }
        }
    }
}

struct MenuBarAppearanceEditor: View {
    @EnvironmentObject var settings: SettingsEditingSession

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { settings.settings.menuBarOpacity * 100 },
            set: { settings.settings.menuBarOpacity = $0 / 100 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Menu Bar Tint").font(.headline)
                Spacer()
                Button("Reset", action: resetTintSettings)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding([.top, .horizontal])

            ToggleRow(title: "Liquid Glass Look", description: "Apply a shiny, glass-like effect to the menu bar's background.", isOn: $settings.settings.menuBarLiquidGlass)

            if settings.settings.menuBarLiquidGlass {
                Divider().padding(.leading, 20)
                LiquidGlassStylePickerRow(selection: $settings.settings.menuBarLiquidGlassStyle)

                Divider().padding(.leading, 20)
                ToggleRow(
                    title: "Frosted Overlay",
                    description: "Layer frosted liquid glass on top of the base glass, matching the lock screen treatment.",
                    isOn: $settings.settings.menuBarBlur
                )
            }

            Divider().padding(.leading, 20)

            HStack {
                Text("Background Style")
                Spacer()
                Picker("", selection: $settings.settings.menuBarTintStyle) {
                    Text("None").tag("none"); Text("Solid").tag("solid"); Text("Gradient").tag("gradient")
                }.labelsHidden().frame(width: 200)
            }.padding()

            if settings.settings.menuBarTintStyle == "solid" {
                solidColorPicker
            } else if settings.settings.menuBarTintStyle == "gradient" {
                gradientColorEditor
            }

            Divider().padding(.leading, 20)

                    CustomSliderRowView(label: "Master Opacity", value: opacityBinding, range: 0...100, specifier: "%.0f%%")

            if !settings.settings.menuBarLiquidGlass {
                Divider().padding(.leading, 20)
                ToggleRow(title: "Enable Transparency Blur", description: "Apply a frosted glass effect to the menu bar background.", isOn: $settings.settings.menuBarBlur)
            }
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: settings.settings.menuBarLiquidGlass)
        .animation(.default, value: settings.settings.menuBarBlur)
        .animation(.default, value: settings.settings.menuBarTintStyle)
    }

    @ViewBuilder
    private var solidColorPicker: some View {
        ColorPicker("Color", selection: $settings.settings.menuBarSolidColor.color, supportsOpacity: true)
            .padding()
            .transition(.opacity)
    }

    @ViewBuilder
    private var gradientColorEditor: some View {
        VStack(alignment: .leading) {
            CustomSliderRowView(label: "Angle", value: $settings.settings.menuBarGradientAngle, range: 0...360, specifier: "%.0f°")
                .padding(.horizontal)

            Text("Gradient Colors").font(.subheadline).padding(.horizontal)

            ForEach($settings.settings.menuBarGradientColors) { $color in
                VStack(spacing: 8) {
                    HStack {
                        ColorPicker("Color Stop", selection: $color.color, supportsOpacity: true)
                        Spacer()
                        Button(action: {
                            guard settings.settings.menuBarGradientColors.count > 1 else { return }
                            let doomed = color.id
                            DispatchQueue.main.async {
                                settings.settings.menuBarGradientColors.removeAll { $0.id == doomed }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }.buttonStyle(.plain).disabled(settings.settings.menuBarGradientColors.count <= 1)
                    }
                    DeferredValueEditor(value: $color.location.asDouble) { draft, onEditingChanged in
                        Slider(
                            value: draft,
                            in: 0...1,
                            label: { Text("Location") },
                            onEditingChanged: onEditingChanged
                        )
                    }
                }.padding(.horizontal)
            }

            Button(action: {
                var colors = settings.settings.menuBarGradientColors
                let newStop = CodableColor(color: colors.last?.color ?? .black, location: 1.0)
                colors.append(newStop)
                settings.settings.menuBarGradientColors = colors
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Color Stop")
                }
            }.buttonStyle(.plain).tint(.accentColor).padding([.top, .horizontal])
        }
        .padding(.vertical)
        .transition(.opacity)
    }

    private func resetTintSettings() {
        var updated = settings.settings
        updated.menuBarLiquidGlass = false
        updated.menuBarLiquidGlassStyle = .frosted
        updated.menuBarTintStyle = "none"
        updated.menuBarSolidColor = CodableColor(color: .clear)
        updated.menuBarGradientAngle = 0.0
        updated.menuBarGradientColors = [
            CodableColor(color: .white, location: 0),
            CodableColor(color: .black, location: 1)
        ]
        updated.menuBarOpacity = 1.0
        updated.menuBarBlur = false
        settings.settings = updated
    }
}

struct MenuBarAppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession

    private var verticalPaddingBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(settings.settings.menuBarVerticalPadding) },
            set: { settings.settings.menuBarVerticalPadding = CGFloat($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu Bar Style (Beta)").font(.title2.bold())
                    Text("Customize the look and feel of your Mac's menu bar.").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Reset All", action: resetAllAppearanceSettings)
                    .buttonStyle(.plain)
            }

            MenuBarAppearanceEditor()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Border Thickness"); Spacer()
                    Picker("Border", selection: $settings.settings.menuBarBorderWidth) {
                        Text("No Border").tag(CGFloat(0)); Text("1px").tag(CGFloat(1)); Text("2px").tag(CGFloat(2)); Text("3px").tag(CGFloat(3))
                    }.labelsHidden().frame(width: 120)
                }.padding()
                Divider().padding(.horizontal)
                ColorPicker("Border Color", selection: $settings.settings.menuBarBorderColor.color, supportsOpacity: true).padding()
            }.modifier(SettingsContainerModifier())

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { settings.settings.menuBarShapeStyle == "rounded" },
                    set: { if $0 { settings.settings.menuBarShapeStyle = "rounded" } else if settings.settings.menuBarShapeStyle == "rounded" { settings.settings.menuBarShapeStyle = "none" } }
                )) {
                    Text("Rounded menu bar")
                }.padding()

                Divider().padding(.horizontal)

                Toggle(isOn: Binding(
                    get: { settings.settings.menuBarShapeStyle == "roundedSplit" },
                    set: { if $0 { settings.settings.menuBarShapeStyle = "roundedSplit" } else if settings.settings.menuBarShapeStyle == "roundedSplit" { settings.settings.menuBarShapeStyle = "none" } }
                )) {
                    Text("Rounded separate sides")
                }.padding()

                Divider().padding(.horizontal)
                CustomSliderRowView(label: "Vertical Padding", value: verticalPaddingBinding, range: 0...10, specifier: "%.0fpx")

            }.modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.menuBarShapeStyle)
        }
    }

    private func resetAllAppearanceSettings() {
        var updated = settings.settings
        updated.menuBarLiquidGlass = false
        updated.menuBarLiquidGlassStyle = .frosted
        updated.menuBarTintStyle = "none"
        updated.menuBarSolidColor = CodableColor(color: .clear)
        updated.menuBarGradientAngle = 0.0
        updated.menuBarGradientColors = [
            CodableColor(color: .white, location: 0),
            CodableColor(color: .black, location: 1)
        ]
        updated.menuBarOpacity = 1.0
        updated.menuBarBlur = false

        updated.menuBarBorderWidth = 0
        updated.menuBarBorderColor = CodableColor(color: .black)

        updated.menuBarShapeStyle = "none"
        updated.menuBarVerticalPadding = 0
        settings.settings = updated
    }
}

struct MenuBarSpacingSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @State private var spacingManager: MenuBarSpacingManager?

    private var spacingBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(settings.settings.menuBarSpacing) },
            set: { settings.settings.menuBarSpacing = Int($0) }
        )
    }

    private var paddingBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(settings.settings.menuBarSelectionPadding) },
            set: { settings.settings.menuBarSelectionPadding = Int($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Spacing (Beta)").font(.title2.bold())
                Text("Fine-tune the spacing and padding between all menu bar items. Changes require a menu bar refresh to apply.").font(.caption).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                CustomSliderRowView(label: "Spacing", value: spacingBinding, range: 1...50, specifier: "%.0f")
                Divider().padding(.leading, 20)
                CustomSliderRowView(label: "Padding", value: paddingBinding, range: 1...50, specifier: "%.0f")

                HStack {
                    Button("Reset to System Default") {
                        spacingManager?.restoreDefaults()
                    }
                    .disabled(spacingManager == nil)

                    Spacer()

                    Button("Apply & Refresh Menu Bar") {
                        spacingManager?.applyChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(spacingManager == nil)
                }
                .padding()

            }.modifier(SettingsContainerModifier())
        }
        .onAppear {
            if spacingManager == nil {
                spacingManager = MenuBarSpacingManager()
            }
        }
    }
}

struct ControlItemIconPreview: View {
    let iconStyle: ControlItemIconStyle
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconStyle.previewSymbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 60, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.15 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )

            Text(iconStyle.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

extension View {
    @ViewBuilder
    func dynamicXAxis(for range: TimeRange, isVisible: Bool) -> some View {
        if isVisible {
            switch range {
            case .last24Hours:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
            case .last7Days:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) { _ in AxisValueLabel(format: .dateTime.weekday()) } }
            case .lastMonth, .custom:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            case .lastYear:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            }
        } else {
            self.chartXAxis(.hidden)
        }
    }
}

extension View {
    func chartInteractionOverlay<T: Identifiable>(
        proxy: ChartProxy,
        data: [T],
        keyPath: KeyPath<T, Date>,
        selectedItem: Binding<T?>
    ) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if let date: Date = proxy.value(atX: value.location.x) {
                                let closest = data.min {
                                    abs($0[keyPath: keyPath].timeIntervalSince(date)) <
                                    abs($1[keyPath: keyPath].timeIntervalSince(date))
                                }
                                selectedItem.wrappedValue = closest
                            }
                        }
                        .onEnded { _ in
                            selectedItem.wrappedValue = nil
                        }
                )
        }
    }
}

struct ModernSegmentedPicker: View {
    @Binding var selection: String
    let options: [String]

    @Namespace private var pickerNamespace

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(.headline.weight(.bold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                                    .matchedGeometryEffect(id: "pickerPill", in: pickerNamespace)
                            }
                        }
                    )
                    .foregroundColor(selection == option ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.7)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

typealias GeminiSettingsView = IntelligenceSettingsView

// MARK: - Legacy Settings View Shims

// MARK: - Task Runner Interface

struct IntelligenceRunnerView: View {
    let apiKey: String
    var backend: LLMBackend = .auto
    var geminiSpeedMode: GeminiSpeedMode = .fast
    @ObservedObject private var vm: IntelligenceNotchViewModel
    @State private var isRunningScreenshotDebug = false

    init(
        apiKey: String,
        backend: LLMBackend = .gemini,
        geminiSpeedMode: GeminiSpeedMode = .fast,
        vm: IntelligenceNotchViewModel? = nil
    ) {
        self.apiKey = apiKey
        self.backend = backend
        self.geminiSpeedMode = geminiSpeedMode
        let resolvedVM = vm ?? (NSApp.delegate as? AppDelegate)?.intelligenceViewModel ?? IntelligenceNotchViewModel()
        self._vm = ObservedObject(wrappedValue: resolvedVM)
    }

    private var isLaunchDisabled: Bool {
        if vm.taskInput.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return !backend.isKeyConfigured && backend.resolveAPIKey(fallbackGeminiKey: apiKey).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Describe a task...", text: $vm.taskInput)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15)))
                    .onSubmit {
                        if !vm.isRunning && !isLaunchDisabled {
                            let activeKey = backend.resolveAPIKey(fallbackGeminiKey: apiKey)
                            vm.run(
                                apiKey: activeKey,
                                backend: backend,
                                geminiSpeedMode: geminiSpeedMode
                            )
                        }
                    }

                if vm.isRunning {
                    Button(action: vm.stop) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        let activeKey = backend.resolveAPIKey(fallbackGeminiKey: apiKey)
                        vm.run(
                            apiKey: activeKey,
                            backend: backend,
                            geminiSpeedMode: geminiSpeedMode
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .background(isLaunchDisabled ? Color.gray.opacity(0.3) : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(isLaunchDisabled)
                }

                Button {
                    runScreenshotDebug()
                } label: {
                    Image(systemName: isRunningScreenshotDebug ? "camera.fill" : "camera")
                        .foregroundStyle(isRunningScreenshotDebug ? .yellow : .white)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .help("Capture 10 screenshots at 1.5 second intervals")
                .disabled(isRunningScreenshotDebug)
            }

            if backend == .hackclub {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hack Club AI Integration")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("Hack Club API Key", text: Binding(
                            get: { APIKeyManager.shared.hackClubAPIKey },
                            set: { APIKeyManager.shared.hackClubAPIKey = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12)))

                        TextField("Model Name", text: Binding(
                            get: { UserDefaults.standard.string(forKey: "hackClubModel") ?? "qwen/qwen3-32b" },
                            set: { UserDefaults.standard.set($0, forKey: "hackClubModel") }
                        ))
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12)))
                    }
                }
                .padding(.top, 4)
            }

            if vm.isRunning && vm.subtaskProgress.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Subtask \(vm.subtaskProgress.current) of \(vm.subtaskProgress.total)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView().scaleEffect(0.6)
                    }
                    ProgressView(value: Double(vm.subtaskProgress.current),
                                 total: Double(vm.subtaskProgress.total))
                        .tint(.blue)
                }
            }

            if let result = vm.lastResult {
                HStack(spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .orange)
                    Text(result.success ? "Completed" : "Partial")
                        .font(.caption.bold())
                    Text("· \(result.subtasksCompleted)/\(result.subtasksTotal) subtasks · \(result.actionsTaken) actions · \(String(format: "%.1fs", result.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !vm.logEntries.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(vm.logEntries.reversed()) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(
                                    line.isError ? Color.red :
                                    line.isSubtask ? Color.orange :
                                    Color.secondary
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 140)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func runScreenshotDebug() {
        guard !isRunningScreenshotDebug else { return }
        isRunningScreenshotDebug = true

        Task { @MainActor in
            defer { isRunningScreenshotDebug = false }

            let perception = ScreenPerception()
            vm.logEntries.append(.init(text: " Screenshot debug started (10 captures / 1.5s)", isError: false, isSubtask: true))

            for index in 1...10 {
                let (image, elements) = await perception.captureAnnotatedScreen()
                let imageNote = image == nil ? "no image" : "image ok"
                vm.logEntries.append(.init(text: " [\(index)/10] \(imageNote) · \(elements.count) elements", isError: false, isSubtask: true))
                if index < 10 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
            }

            vm.logEntries.append(.init(text: " Screenshot debug finished", isError: false, isSubtask: true))
        }
    }
}

// MARK: - Focus Session Settings

struct FocusSessionSettingsView: View {
    private struct AppCandidate: Identifiable, Sendable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    @EnvironmentObject var settings: SettingsEditingSession
    @StateObject private var shortcutRecorder = GlobalShortcutRecorder.shared
    @StateObject private var ambient = FocusAmbientSoundManager.shared
    @StateObject private var shortcutsCatalog = ShortcutsCatalog.shared
    @State private var newBlockedApp: String = ""
    @State private var newBlockedSite: String = ""
    @State private var showingAddSchedule = false
    @State private var appCandidates: [AppCandidate] = []

    nonisolated private static func loadInstalledApps() -> [AppCandidate] {
        InstalledApplications.namesAndBundleIDs().map { AppCandidate(name: $0.name, bundleID: $0.bundleID) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Focus Sessions")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                streakSection
                durationSection
                schedulingSection
                liveActivityToggleSection
                blockingSection
                environmentSection
                automationSection
                historySection
            }
            .padding(25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task {
            guard appCandidates.isEmpty else { return }
            let candidates = await Task.detached(priority: .utility) {
                Self.loadInstalledApps()
            }.value
            guard !Task.isCancelled else { return }
            appCandidates = candidates
        }
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Streaks")
            Text("Miss a day without breaking your streak by reporting immunity days at least 3 days in advance (unlimited). If a streak still breaks, spend a streak pass to revive it — everyone gets a few free every month by plan.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

            FocusStreakPanelView(expanded: true)
                .environmentObject(FocusSessionManager.shared)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .modifier(SettingsContainerModifier())
    }

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Scheduling")
            Text("Auto-start a focus session at a set time of day — daily, on specific days of the week, weekly, monthly, or once.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if settings.settings.scheduledFocusSessions.isEmpty {
                Text("No scheduled sessions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach($settings.settings.scheduledFocusSessions) { $schedule in
                    FocusScheduleRowView(schedule: $schedule)
                    Divider().opacity(0.3).padding(.horizontal, 16)
                }
            }

            Divider().opacity(0.3).padding(.horizontal, 16)
            Button {
                showingAddSchedule = true
            } label: {
                Label("Add Schedule", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .modifier(SettingsContainerModifier())
        .sheet(isPresented: $showingAddSchedule) {
            AddFocusScheduleView().environmentObject(settings)
        }
    }

    private var liveActivityToggleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Widget & Activity")
            ToggleRow(
                title: "Show in Notch",
                description: "Display the focus session as a live activity in the notch while it's running.",
                isOn: $settings.settings.focusSessionLiveActivityEnabled
            )
            Divider().opacity(0.3).padding(.horizontal, 16)
            ToggleRow(
                title: "Show Time Instead of Ring",
                description: "Show the remaining time on the right side instead of the completing progress ring.",
                isOn: $settings.settings.focusSessionLiveActivityShowTime
            )
            Divider().opacity(0.3).padding(.horizontal, 16)
            ToggleRow(
                title: "Break & Session Notifications",
                description: "Get a notification when a focus block ends and a break starts, when a break ends, and when the session finishes.",
                isOn: $settings.settings.focusNotificationsEnabled
            )
            Divider().opacity(0.3).padding(.horizontal, 16)
            ToggleRow(
                title: "Click to Show Detail View",
                description: "Clicking the focus session activity opens the full detail view.",
                isOn: $settings.settings.clickToShowFocusSessionView
            )
        }
        .modifier(SettingsContainerModifier())
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Session Timing")
            HStack {
                Text("Focus Duration:")
                    .font(.system(size: 13))
                Spacer()
                TextField("Minutes", value: Binding(
                    get: { settings.settings.focusSessionDuration / 60 },
                    set: { settings.settings.focusSessionDuration = max(1, $0) * 60 }
                ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .frame(width: 62)
                    .multilineTextAlignment(.trailing)
                    .help("No limit — enter any number of minutes")
                Text("min")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().opacity(0.3).padding(.horizontal, 16)

            ToggleRow(title: "Enable Breaks", description: "Automatically start a break after each focus block.", isOn: $settings.settings.focusBreakEnabled)
            if settings.settings.focusBreakEnabled {
                Divider().opacity(0.3).padding(.horizontal, 16)
                HStack {
                    Text("Break Duration:")
                        .font(.system(size: 13))
                    Spacer()
                    TextField("Minutes", value: Binding(
                        get: { settings.settings.focusBreakDuration / 60 },
                        set: { settings.settings.focusBreakDuration = max(0, $0) * 60 }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .frame(width: 62)
                        .multilineTextAlignment(.trailing)
                        .help("No limit — enter any number of minutes (0 disables the break)")
                    Text("min")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private var blockingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("App & Website Blocking")
            ToggleRow(title: "Enable Blocking", description: "Block distracting apps and websites during focus sessions.", isOn: $settings.settings.focusBlockingEnabled)
            if settings.settings.focusBlockingEnabled {
                Divider().opacity(0.3).padding(.horizontal, 16)
                Picker("Blocking mode", selection: $settings.settings.focusBlockingMode) {
                    ForEach(FocusBlockingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Text(settings.settings.focusBlockingMode.blurb)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 8)

                Divider().opacity(0.3).padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    Text("Blocking Intensity")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 6)
                Text("How aggressively blocked apps (and websites) are handled during a session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                if FocusSessionManager.shared.isSessionActive {
                    Label("Intensity can't be changed while a session is running", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                ForEach(FocusIntensity.allCases) { level in
                    Button {
                        guard !FocusSessionManager.shared.isSessionActive else { return }
                        settings.settings.focusIntensity = level
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: level.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(settings.settings.focusIntensity == level ? .green : .secondary)
                                .frame(width: 22)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(level.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)
                                    if settings.settings.focusIntensity == level {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.green)
                                    }
                                }
                                Text(level.blurb)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(settings.settings.focusIntensity == level ? Color.green.opacity(0.12) : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .opacity(FocusSessionManager.shared.isSessionActive ? 0.45 : 1.0)
                }
                .padding(.bottom, 6)

                Divider().opacity(0.3).padding(.horizontal, 16)

                if settings.settings.focusBlockingMode == .allowlist {
                    Divider().opacity(0.3).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Allowed Apps")
                            .font(.caption.bold()).padding(.horizontal, 16).padding(.top, 10)
                        Picker("Add app", selection: $newBlockedApp) {
                            Text("Select an app…").tag("")
                            ForEach(appCandidates, id: \.bundleID) { candidate in
                                Text(candidate.name).tag(candidate.bundleID)
                            }
                        }
                        .padding(.horizontal, 16)
                        HStack {
                            Spacer()
                            Button("Add") {
                                guard !newBlockedApp.isEmpty else { return }
                                settings.settings.focusAllowedApps.insert(newBlockedApp)
                                newBlockedApp = ""
                            }
                            .disabled(newBlockedApp.isEmpty)
                            .padding(.trailing, 16)
                        }
                        if !settings.settings.focusAllowedApps.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 4) {
                                ForEach(Array(settings.settings.focusAllowedApps), id: \.self) { bundleID in
                                    let name = appCandidates.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
                                    chipView(name) { settings.settings.focusAllowedApps.remove(bundleID) }
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    }
                } else {
                    Divider().opacity(0.3).padding(.horizontal, 16)
                    ToggleRow(title: "Block During Breaks", description: "Keep blocking active while on break.", isOn: $settings.settings.focusBlockingDuringBreaks)

                    Divider().opacity(0.3).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blocked Apps")
                            .font(.caption.bold()).padding(.horizontal, 16).padding(.top, 10)
                    Picker("Add app", selection: $newBlockedApp) {
                        Text("Select an app…").tag("")
                        ForEach(appCandidates, id: \.bundleID) { candidate in
                            Text(candidate.name).tag(candidate.bundleID)
                        }
                    }
                    .padding(.horizontal, 16)
                    HStack {
                        Spacer()
                        Button("Add") {
                            guard !newBlockedApp.isEmpty else { return }
                            settings.settings.focusBlockedApps.insert(newBlockedApp)
                            newBlockedApp = ""
                        }
                        .disabled(newBlockedApp.isEmpty)
                        .padding(.trailing, 16)
                    }
                    if !settings.settings.focusBlockedApps.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 4) {
                            ForEach(Array(settings.settings.focusBlockedApps), id: \.self) { bundleID in
                                let name = appCandidates.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
                                chipView(name) { settings.settings.focusBlockedApps.remove(bundleID) }
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }

                    Divider().opacity(0.3).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blocked Websites")
                            .font(.caption.bold()).padding(.horizontal, 16).padding(.top, 10)
                        HStack {
                            TextField("e.g. twitter.com", text: $newBlockedSite)
                                .textFieldStyle(.roundedBorder)
                                .padding(.leading, 16)
                            Button("Add") {
                                let trimmed = newBlockedSite
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "https://", with: "")
                                    .replacingOccurrences(of: "http://", with: "")
                                    .replacingOccurrences(of: "www.", with: "")
                                guard !trimmed.isEmpty else { return }
                                settings.settings.focusBlockedWebsites.insert(trimmed)
                                newBlockedSite = ""
                            }
                            .disabled(newBlockedSite.trimmingCharacters(in: .whitespaces).isEmpty)
                            .padding(.trailing, 16)
                        }
                        if !settings.settings.focusBlockedWebsites.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 4) {
                                ForEach(Array(settings.settings.focusBlockedWebsites), id: \.self) { site in
                                    chipView(" \(site)") { settings.settings.focusBlockedWebsites.remove(site) }
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    }
                    .padding(.bottom, 8)
                    }
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Environment")
            Text("Apply environment adjustments to the whole Mac while a session runs.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)

            ToggleRow(title: "Dim Inactive Apps", description: "Darken windows you're not using so the active app stands out and visual clutter recedes.", isOn: $settings.settings.focusDimInactiveApps)
            if settings.settings.focusDimInactiveApps {
                Divider().opacity(0.3).padding(.horizontal, 16)
                HStack {
                    Text("Dim Intensity:")
                        .font(.system(size: 13))
                    Spacer()
                    DeferredSlider(value: $settings.settings.focusDimInactiveOpacity, in: 0.2...1.0)
                        .frame(width: 160)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                Divider().opacity(0.3).padding(.horizontal, 16)
                ToggleRow(title: "Pause in Mission Control", description: "Temporarily remove the dim layer while Mission Control is open so you can actually see the apps in the Exposé grid.", isOn: $settings.settings.focusDisableDimInMissionControl)
            }

            Divider().opacity(0.3).padding(.horizontal, 16)
            ToggleRow(title: "Hide Wallpaper", description: "Cover the desktop wallpaper and icons with black for the duration of the session.", isOn: $settings.settings.focusHideWallpaper)

            Divider().opacity(0.3).padding(.horizontal, 16)
            ToggleRow(title: "Limit Visible Apps", description: "Keep only a few apps on screen; switching to another tucks the oldest one away (restored when the session ends).", isOn: $settings.settings.focusAppLimitEnabled)
            if settings.settings.focusAppLimitEnabled {
                Divider().opacity(0.3).padding(.horizontal, 16)
                HStack {
                    Text("Max visible apps:")
                        .font(.system(size: 13))
                    Spacer()
                    Stepper(value: $settings.settings.focusAppLimit, in: 1...6) {
                        Text("\(settings.settings.focusAppLimit)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            Divider().opacity(0.3).padding(.horizontal, 16)
            ToggleRow(title: "Ambient Sounds", description: "Play generated white/pink/brown noise or rain to mask noisy surroundings. Starts automatically with each session.", isOn: $settings.settings.focusAmbientSoundEnabled)
            if settings.settings.focusAmbientSoundEnabled {
                Divider().opacity(0.3).padding(.horizontal, 16)
                Picker("Sound", selection: $settings.settings.focusAmbientSoundType) {
                    ForEach(FocusAmbientSoundType.allCases) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider().opacity(0.3).padding(.horizontal, 16)
                HStack(spacing: 12) {
                    Button(action: { ambient.toggle() }) {
                        Label(ambient.isPlaying ? "Stop" : "Preview", systemImage: ambient.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Text("Volume")
                        .font(.system(size: 13))
                    DeferredSlider(
                        value: Binding(
                            get: { settings.settings.focusAmbientSoundVolume },
                            set: {
                                ambient.volume = $0
                                settings.settings.focusAmbientSoundVolume = $0
                            }
                        ),
                        in: 0...1,
                        onDraftChange: { ambient.volume = $0 }
                    )
                    .frame(width: 110)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .modifier(SettingsContainerModifier())
        .onChange(of: settings.settings.focusAmbientSoundType) { _, newType in
            if ambient.isPlaying { ambient.setType(newType) }
        }
        .onChange(of: settings.settings.focusAmbientSoundEnabled) { _, enabled in
            if !enabled, ambient.isPlaying { ambient.stop() }
        }
    }

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Automation")

            Text("Press this shortcut from anywhere to start or pause a focus session.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            Button(action: {
                if shortcutRecorder.isRecording {
                    shortcutRecorder.stopRecording()
                } else {
                    shortcutRecorder.startRecording { key, flags in
                        settings.settings.focusStartShortcut = KeyboardShortcut(key: key, modifiers: flags)
                    }
                }
            }) {
                HStack {
                    if shortcutRecorder.isRecording {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Recording... (Esc to cancel)")
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        Image(systemName: "keyboard")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text("\(KeyboardShortcutHelper.description(for: settings.settings.focusStartShortcut.modifiers)) \(settings.settings.focusStartShortcut.key)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.bottom, 12)

            Divider().opacity(0.3).padding(.horizontal, 16)

            HStack(spacing: 8) {
                Image(systemName: "link.icloud")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                Text("System Clock & Shortcuts")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 6)
            Text("Sapphire automatically uses Apple's standard Clock shortcut names (\"Start Timer\", \"Start Stopwatch\", etc.). If iCloud sync is enabled and those Clock shortcuts are present on this Mac, they run automatically during sessions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
            ToggleRow(title: "Sync with System Clock", description: "Mirror focus sessions to the system Clock app via Shortcuts.", isOn: $settings.settings.focusShortcutsEnabled)
            if settings.settings.focusShortcutsEnabled {
                Divider().opacity(0.3).padding(.horizontal, 16)
                Picker("Sync mode", selection: $settings.settings.focusShortcutSyncMode) {
                    ForEach(FocusShortcutSyncMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            Divider().opacity(0.3).padding(.horizontal, 16)
            Text("Run a Shortcut when a session starts / ends — e.g. turn on Do Not Disturb.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
            Picker("On session start", selection: $settings.settings.focusStartShortcutName) {
                Text("None").tag("")
                ForEach(shortcutsCatalog.installedNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            Picker("On session end", selection: $settings.settings.focusEndShortcutName) {
                Text("None").tag("")
                ForEach(shortcutsCatalog.installedNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .padding(.bottom, 8)
        }
        .modifier(SettingsContainerModifier())
        .onAppear {
            FocusSessionManager.refreshInstalledShortcuts()
        }
    }

    private var historySection: some View {
        let fm = FocusSessionManager.shared
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Stats & History")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCard(title: "Today", value: FocusSessionManager.format(fm.completedToday), icon: "sun.max.fill", color: .green)
                statCard(title: "Streak", value: "\(fm.currentStreak)d", icon: "flame.fill", color: .orange)
                statCard(title: "Sessions", value: "\(fm.totalSessionCountAllTime)", icon: "checkmark.seal.fill", color: .blue)
                statCard(title: "All Time", value: FocusSessionManager.format(fm.totalFocusTimeAllTime), icon: "clock.fill", color: .purple)
                statCard(title: "Average", value: FocusSessionManager.format(fm.averageSessionDuration), icon: "gauge.medium", color: .cyan)
                if let best = fm.bestDay {
                    statCard(title: "Best Day", value: FocusSessionManager.format(best.seconds), icon: "trophy.fill", color: .yellow)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            let week = fm.weeklyData
            let maxWeek = max(week.map(\.seconds).max() ?? 1, 1)
            if week.contains(where: { $0.seconds > 0 }) {
                Divider().opacity(0.3).padding(.horizontal, 16)
                Text("Last 7 Days")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(week.indices, id: \.self) { i in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(week[i].seconds > 0 ? Color.green.opacity(0.7) : Color.secondary.opacity(0.15))
                                .frame(height: max(4, CGFloat(week[i].seconds / maxWeek) * 70))
                            Text(week[i].label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }

            if !fm.history.isEmpty {
                Divider().opacity(0.3).padding(.horizontal, 16)
                Text("Recent Sessions")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(fm.history.prefix(10)) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if session.completedBlocks > 1 {
                                    Text("\(session.completedBlocks) blocks")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                            }
                            Spacer()
                            Text(FocusSessionManager.format(session.actualDuration))
                                .font(.caption.monospaced().bold())
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        Divider().opacity(0.15).padding(.leading, 16)
                    }
                }
                .padding(.bottom, 8)
            } else {
                Text("No completed sessions yet. Start one and stay focused! ")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if !fm.history.isEmpty {
                Divider().opacity(0.3).padding(.horizontal, 16)
                HStack {
                    Spacer()
                    Button("Clear History", role: .destructive) {
                        fm.clearAllHistory()
                    }
                    .font(.caption)
                    .padding(.trailing, 16).padding(.vertical, 10)
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(NSLocalizedString(title, comment: "Settings title"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: "Settings title"))
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 12).padding(.horizontal, 16).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chipView(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(text).font(.caption).lineLimit(1)
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

// MARK: - Scheduled Focus Sessions

private struct FocusScheduleRowView: View {
    @EnvironmentObject private var settings: SettingsEditingSession
    @Binding var schedule: ScheduledFocusSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundColor(schedule.isActive ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(schedule.startTime, style: .time)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(schedule.isActive ? .primary : .secondary)
                    Text(schedule.repeatDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            SettingsSwitch(isOn: $schedule.isActive)
                .controlSize(.mini)

            Button {
                settings.settings.scheduledFocusSessions.removeAll { $0.id == schedule.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete schedule")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        var text = "\(Int(schedule.duration / 60)) min session"
        if schedule.isActive,
           let next = FocusScheduleManager.shared.nextFireDate(for: schedule) {
            let day = Calendar.current.isDateInToday(next)
                ? "today" : (Calendar.current.isDateInTomorrow(next) ? "tomorrow" : next.formatted(date: .abbreviated, time: .omitted))
            text += " · next \(day) at \(next.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }
}

private struct AddFocusScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsEditingSession
    private struct WeekdayToken: Identifiable {
        let number: Int
        let label: String
        var id: Int { number }
    }

    private static let weekdayChoices: [WeekdayToken] = [
        WeekdayToken(number: 2, label: "Mon"),
        WeekdayToken(number: 3, label: "Tue"),
        WeekdayToken(number: 4, label: "Wed"),
        WeekdayToken(number: 5, label: "Thu"),
        WeekdayToken(number: 6, label: "Fri"),
        WeekdayToken(number: 7, label: "Sat"),
        WeekdayToken(number: 1, label: "Sun"),
    ]

    @State private var startTime = Date().addingTimeInterval(60 * 60)
    @State private var repeatInterval: FocusScheduleRepeat = .daily
    @State private var repeatWeekdays: [Int] = []
    @State private var durationMinutes: Double = 90

    var body: some View {
        VStack(spacing: 20) {
            Text("New Focus Schedule")
                .font(.title.bold())

            VStack(spacing: 16) {
                DatePicker("Start Time:", selection: $startTime, displayedComponents: .hourAndMinute)

                Picker("Repeat:", selection: $repeatInterval) {
                    ForEach(FocusScheduleRepeat.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }

                if repeatInterval == .custom {
                    Divider().opacity(0.2)
                    weekdayPicker
                }

                HStack {
                    Text("Duration:")
                    Spacer()
                    TextField("Minutes", value: Binding(
                        get: { durationMinutes },
                        set: { durationMinutes = max(1, $0) }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .frame(width: 62)
                        .multilineTextAlignment(.trailing)
                        .help("No limit — enter any number of minutes")
                    Text("min")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Text("Scheduled sessions respect your blocking, environment, and ambient-sound settings — they behave exactly like sessions you start manually.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .modifier(SettingsContainerModifier())

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add Schedule") {
                    var schedule = ScheduledFocusSession()
                    schedule.startTime = startTime
                    schedule.repeatInterval = repeatInterval
                    schedule.duration = durationMinutes * 60
                    if repeatInterval == .custom {
                        schedule.repeatWeekdays = repeatWeekdays
                    }
                    settings.settings.scheduledFocusSessions.append(schedule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 420)
        .onAppear {
            durationMinutes = settings.settings.focusSessionDuration / 60
        }
    }

    private var weekdayPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Repeat on")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(repeatWeekdays.isEmpty ? "Every day" : "Clear all") {
                    repeatWeekdays = []
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.green)
            }

            HStack(spacing: 6) {
                ForEach(Self.weekdayChoices) { token in
                    weekdayPill(token)
                }
            }
        }
    }

    private func weekdayPill(_ token: WeekdayToken) -> some View {
        let isOn = repeatWeekdays.contains(token.number)
        return Button {
            if isOn {
                repeatWeekdays.removeAll { $0 == token.number }
            } else {
                repeatWeekdays.append(token.number)
            }
        } label: {
            Text(token.label)
                .font(.system(size: 11, weight: isOn ? .bold : .medium))
                .foregroundColor(isOn ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    isOn ? Color.green : Color.white.opacity(0.08),
                    in: Capsule()
                )
        }        .buttonStyle(.plain)
        .help(token.label)
    }
}
