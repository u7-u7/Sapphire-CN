//
//  SettingsComponents.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import AppKit

struct InfoContainer: View {
    let text: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(color)
                .padding(.top, 2)

            Text(NSLocalizedString(text, comment: "Settings information"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(4)
        }
        .padding()
        .roundedCard(fill: color.opacity(0.15), cornerRadius: 16, stroke: color.opacity(0.5))
    }
}

// MARK: - Row Building Blocks

struct SettingsSwitch: View {
    var title: String = ""
    @Binding var isOn: Bool

    var body: some View {
        Toggle(NSLocalizedString(title, comment: "Settings switch"), isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

struct SettingsRowLabel: View {
    let title: String
    var description: String = ""
    var titleFont: Font = .system(size: 14, weight: .medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString(title, comment: "Settings row title"))
                .font(titleFont)
            if !description.isEmpty {
                Text(NSLocalizedString(description, comment: "Settings row description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsIconBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ReorderHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.leading, 8)
    }
}

struct PremiumLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension Binding where Value == Bool {
    func lockedOff(when isLocked: Bool) -> Binding<Bool> {
        Binding(
            get: { isLocked ? false : wrappedValue },
            set: { wrappedValue = isLocked ? false : $0 }
        )
    }

    var negated: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}

extension Binding {
    func membership<Element: Equatable>(of element: Element) -> Binding<Bool> where Value == [Element] {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { isMember in
                if !isMember {
                    wrappedValue.removeAll { $0 == element }
                } else if !wrappedValue.contains(element) {
                    wrappedValue.append(element)
                }
            }
        )
    }
}

extension Binding where Value == CGFloat {
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}

// MARK: - Rows

struct IconToggleRow: View {
    let systemImage: String
    let color: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 15) {
            SettingsIconBadge(systemImage: systemImage, color: color)

            Text(NSLocalizedString(title, comment: "Settings toggle title"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            SettingsSwitch(isOn: $isOn)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}

struct WidgetRowView: View {
    let widgetType: WidgetType
    let enabledWidgetCount: Int
    let isPremiumLocked: Bool
    @EnvironmentObject var settings: SettingsEditingSession

    private var availableBarWidth: CGFloat {
        WidgetLayoutPolicy.availableBarWidth()
    }

    private var enabledWidgetTypes: [WidgetType] {
        settings.settings.enabledWidgetTypes
    }

    private var isAtCapacity: Bool {
        guard !isEnabledBinding.wrappedValue else { return false }
        return !WidgetLayoutPolicy.canFit(
            widgetType,
            in: enabledWidgetTypes,
            availableWidth: availableBarWidth,
            showDividers: settings.settings.showDividersBetweenWidgets,
            bypassSpaceLimit: settings.settings.bypassWidgetSpaceLimit
        )
    }

    private var baseEnabledBinding: Binding<Bool> {
        switch widgetType {
        case .weather: return $settings.settings.weatherWidgetEnabled
        case .calendar: return $settings.settings.calendarWidgetEnabled
        case .shortcuts: return $settings.settings.shortcutsWidgetEnabled
        case .music: return $settings.settings.musicWidgetEnabled
        case .sports: return $settings.settings.sportsWidgetEnabled
        case .finance: return $settings.settings.financeWidgetEnabled
        case .shopify: return $settings.settings.shopifyWidgetEnabled
        case .notes: return $settings.settings.notesWidgetEnabled
        case .clipboard: return $settings.settings.clipboardWidgetEnabled
        case .mirror: return $settings.settings.mirrorWidgetEnabled
        case .battery: return $settings.settings.batteryWidgetEnabled
        case .timer: return $settings.settings.timerWidgetEnabled
        case .focusSession: return $settings.settings.focusSessionWidgetEnabled
        case .storage: return $settings.settings.storageWidgetEnabled
        case .agent: return $settings.settings.aiUsageWidgetEnabled
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        baseEnabledBinding.lockedOff(when: isPremiumLocked)
    }

    var body: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString(widgetType.displayName, comment: "Settings option"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    if isAtCapacity {
                        Text("Not enough notch space on this display.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                SettingsSwitch(isOn: isEnabledBinding)
                    .disabled(isPremiumLocked || (isEnabledBinding.wrappedValue && enabledWidgetCount <= 1) || isAtCapacity)

                if isPremiumLocked {
                    PremiumLockBadge()
                }

                ReorderHandle()
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        }
    }
}

struct LiveActivityRowView: View {
    let activityType: LiveActivityType
    let isPremiumLocked: Bool
    @EnvironmentObject var settings: SettingsEditingSession

    private var baseEnabledBinding: Binding<Bool> {
        switch activityType {
        case .music: return $settings.settings.musicLiveActivityEnabled
        case .weather: return $settings.settings.weatherLiveActivityEnabled
        case .calendar: return $settings.settings.calendarLiveActivityEnabled
        case .reminders: return $settings.settings.remindersLiveActivityEnabled
        case .timers: return $settings.settings.timersLiveActivityEnabled
        case .battery: return $settings.settings.batteryLiveActivityEnabled
        case .eyeBreak: return $settings.settings.eyeBreakLiveActivityEnabled
        case .desktop: return $settings.settings.desktopLiveActivityEnabled
        case .focus: return $settings.settings.focusLiveActivityEnabled
        case .fileShelf: return $settings.settings.fileShelfLiveActivityEnabled
        case .fileProgress: return $settings.settings.fileProgressLiveActivityEnabled
        case .microphone: return $settings.settings.microphoneLiveActivityEnabled
        case .devActivity: return $settings.settings.devActivityEnabled
        case .stats: return $settings.settings.statsLiveActivityEnabled
        case .finance: return $settings.settings.financeLiveActivityEnabled
        case .sports: return $settings.settings.sportsLiveActivityEnabled
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString(activityType.displayName, comment: "Settings option"))
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                SettingsSwitch(isOn: baseEnabledBinding.lockedOff(when: isPremiumLocked))
                    .disabled(isPremiumLocked)
                if isPremiumLocked {
                    PremiumLockBadge()
                }
                ReorderHandle()
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: showsExpandedOptions ? 10 : 18, trailing: 20))

            if showsExpandedOptions {
                expandedOptions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
    }

    private var showsExpandedOptions: Bool {
        !isPremiumLocked && baseEnabledBinding.wrappedValue && (activityType == .sports || activityType == .finance)
    }

    @ViewBuilder
    private var expandedOptions: some View {
        switch activityType {
        case .sports:
            optionToggle(
                "Only when live",
                detail: "Hide the sports activity when no favorite team has a live game.",
                isOn: $settings.settings.sportsLiveActivityWhenLiveOnly
            )
        case .finance:
            optionToggle(
                "Only during market hours",
                detail: "Hide the finance activity outside regular US trading hours.",
                isOn: $settings.settings.financeLiveActivityActiveHoursOnly
            )
        default:
            EmptyView()
        }
    }

    private func optionToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(title, comment: "Live activity option"))
                    .font(.system(size: 12, weight: .semibold))
                Text(NSLocalizedString(detail, comment: "Live activity option detail"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

struct NotificationToggleRowView: View {
    let source: NotificationSource
    @EnvironmentObject var settings: SettingsEditingSession

    private var isEnabledBinding: Binding<Bool> {
        switch source {
        case .iMessage: return $settings.settings.iMessageNotificationsEnabled
        case .faceTime: return $settings.settings.faceTimeNotificationsEnabled
        case .airDrop: return $settings.settings.airDropNotificationsEnabled
        }
    }

    var body: some View {
        IconToggleRow(
            systemImage: source.systemImage,
            color: source.iconColor,
            title: source.displayName,
            isOn: isEnabledBinding
        )
    }
}

struct SystemAppIconView: View {
    let app: SystemApp
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6

    var body: some View {
        CachedAppIconView(url: app.url, size: size, cornerRadius: cornerRadius)
    }
}

struct CachedAppIconView: View {
    let url: URL
    var size: CGFloat
    var cornerRadius: CGFloat

    @State private var icon: NSImage?

    private var requestID: String {
        "\(url.standardizedFileURL.path)#\(Int((size * 2).rounded(.up)))"
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.secondary)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: requestID) {
            icon = nil
            let url = url
            let dimension = size * 2
            let worker = Task.detached(priority: .utility) { () -> NSImage? in
                guard !Task.isCancelled else { return nil }
                return AppIconLoader.icon(for: url, maxDimension: dimension)
            }
            let loaded = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let loaded, !Task.isCancelled else { return }
            icon = loaded
        }
    }
}

struct SystemAppRowView: View {
    let app: SystemApp
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            SystemAppIconView(app: app, size: 28, cornerRadius: 6)

            Text(app.name)
                .font(.system(size: 13))
                .foregroundStyle(.white)

            Spacer()

            SettingsSwitch(isOn: $isEnabled)
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

struct ClearableSearchField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AppTogglesListView: View {
    @ObservedObject private var appFetcher = SystemAppFetcher.shared
    let isEnabled: (SystemApp) -> Binding<Bool>
    var maxHeight: CGFloat = 280
    var showSearch: Bool = false
    var browsersSectionTitle: String = "Browsers"
    var onSelectAll: ((Bool) -> Void)?

    @State private var query = ""

    private struct AppSections {
        var browsers: [SystemApp] = []
        var others: [SystemApp] = []

        var isEmpty: Bool { browsers.isEmpty && others.isEmpty }
    }

    private var filteredSections: AppSections {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = AppSections()

        for app in appFetcher.apps {
            guard trimmed.isEmpty
                    || app.name.localizedCaseInsensitiveContains(trimmed)
                    || app.id.localizedCaseInsensitiveContains(trimmed) else {
                continue
            }

            if app.isBrowser {
                result.browsers.append(app)
            } else {
                result.others.append(app)
            }
        }
        return result
    }

    var body: some View {
        let sections = filteredSections

        VStack(alignment: .leading, spacing: 8) {
            if showSearch {
                ClearableSearchField(placeholder: "Search installed apps", text: $query)
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
            }

            if let onSelectAll {
                HStack(spacing: 12) {
                    Button("Select All") { onSelectAll(true) }
                    Button("Deselect All") { onSelectAll(false) }
                }
                .font(.caption)
                .padding(.horizontal)
            }

            if appFetcher.apps.isEmpty {
                ProgressView("Loading apps…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if sections.isEmpty {
                Text("No matching apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        appSection(browsersSectionTitle, apps: sections.browsers)
                        appSection("Other Apps", apps: sections.others)
                    }
                }
                .frame(maxHeight: maxHeight)
            }
        }
        .onAppear { appFetcher.fetchApps() }
    }

    @ViewBuilder
    private func appSection(_ title: String, apps: [SystemApp]) -> some View {
        if !apps.isEmpty {
            Text(NSLocalizedString(title, comment: "Application group title")).font(.caption).foregroundStyle(.secondary).padding(.vertical, 5)
            ForEach(apps) { app in
                SystemAppRowView(app: app, isEnabled: isEnabled(app))
                if app.id != apps.last?.id {
                    Divider().padding(.leading, 50)
                }
            }
        }
    }
}

struct ReorderableVStack<Item: Identifiable & Equatable, Content: View>: View {
    @Binding var items: [Item]
    @ViewBuilder var content: (Item) -> Content

    @State private var draggingIndex: Int?
    @State private var dragOffset: CGSize = .zero

    init(items: Binding<[Item]>, @ViewBuilder content: @escaping (Item) -> Content) {
        self._items = items
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                content(item)
                    .offset(y: draggingIndex == index ? dragOffset.height : 0)
                    .opacity(draggingIndex == index ? 0.75 : 1)
                    .zIndex(draggingIndex == index ? 1 : 0)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .global)
                            .onChanged { value in
                                if draggingIndex == nil {
                                    draggingIndex = index
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                if let draggingIndex = draggingIndex {
                                    moveItem(from: draggingIndex, with: value)
                                }
                                withAnimation {
                                    self.draggingIndex = nil
                                    dragOffset = .zero
                                }
                            }
                    )

                if index != items.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                }
            }
        }
    }

    private func moveItem(from fromIndex: Int, with value: DragGesture.Value) {
        guard fromIndex < items.count else { return }

        let rowHeight: CGFloat = 61.0
        let verticalTranslation = value.translation.height
        let moveOffset = Int((verticalTranslation / rowHeight).rounded())

        var toIndex = fromIndex + moveOffset
        toIndex = max(0, min(items.count - 1, toIndex))

        if fromIndex != toIndex {
            let itemToMove = items.remove(at: fromIndex)
            items.insert(itemToMove, at: toIndex)
        }
    }
}

struct CustomSliderRowView: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let specifier: String
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var draft: Double
    @State private var isEditing = false

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        specifier: String,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.specifier = specifier
        self.onEditingChanged = onEditingChanged
        self._draft = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString(label, comment: "Settings slider label"))
                Spacer()
                Text(String(format: specifier, draft))
            }
            Slider(
                value: Binding(
                    get: { draft },
                    set: { newValue in
                        draft = newValue
                        if !isEditing {
                            value = newValue
                        }
                    }
                ),
                in: range,
                onEditingChanged: { editing in
                    if editing {
                        isEditing = true
                        draft = value
                    } else {
                        let committedValue = draft
                        isEditing = false
                        if abs(committedValue - value) > .ulpOfOne {
                            value = committedValue
                        }
                    }
                    onEditingChanged?(editing)
                }
            )
        }
        .padding()
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                draft = newValue
            }
        }
    }
}

struct DeferredSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let onDraftChange: ((Double) -> Void)?
    private let onEditingChanged: ((Bool) -> Void)?

    @State private var draft: Double
    @State private var isEditing = false

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        onDraftChange: ((Double) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.onDraftChange = onDraftChange
        self.onEditingChanged = onEditingChanged
        self._draft = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        Group {
            if let step {
                Slider(
                    value: draftBinding,
                    in: range,
                    step: step,
                    onEditingChanged: handleEditingChanged
                )
            } else {
                Slider(
                    value: draftBinding,
                    in: range,
                    onEditingChanged: handleEditingChanged
                )
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                draft = newValue
            }
        }
    }

    private var draftBinding: Binding<Double> {
        Binding(
            get: { draft },
            set: { newValue in
                draft = newValue
                onDraftChange?(newValue)
                if !isEditing {
                    value = newValue
                }
            }
        )
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing {
            isEditing = true
            draft = value
        } else {
            let committedValue = draft
            isEditing = false
            if abs(committedValue - value) > .ulpOfOne {
                value = committedValue
            }
        }
        onEditingChanged?(editing)
    }
}

struct DeferredValueEditor<Content: View>: View {
    @Binding private var value: Double
    private let onDraftChange: ((Double) -> Void)?
    private let content: (Binding<Double>, @escaping (Bool) -> Void) -> Content

    @State private var draft: Double
    @State private var isEditing = false

    init(
        value: Binding<Double>,
        onDraftChange: ((Double) -> Void)? = nil,
        @ViewBuilder content: @escaping (Binding<Double>, @escaping (Bool) -> Void) -> Content
    ) {
        self._value = value
        self.onDraftChange = onDraftChange
        self.content = content
        self._draft = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        content(draftBinding, handleEditingChanged)
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if !isEditing {
                    draft = newValue
                }
            }
    }

    private var draftBinding: Binding<Double> {
        Binding(
            get: { draft },
            set: { newValue in
                draft = newValue
                onDraftChange?(newValue)
                if !isEditing {
                    value = newValue
                }
            }
        )
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing {
            isEditing = true
            draft = value
        } else {
            let committedValue = draft
            isEditing = false
            if abs(committedValue - value) > .ulpOfOne {
                value = committedValue
            }
        }
    }
}

struct SettingsContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .roundedCard(fill: Color.black.opacity(0.15), cornerRadius: 24, stroke: Color.white.opacity(0.1))
    }
}

struct SettingsSectionHeader: View {
    let title: LocalizedStringKey
    var description: LocalizedStringKey? = nil

    var body: some View {
        Text(title)
            .font(.headline)
            .padding([.top, .horizontal])
            .frame(maxWidth: .infinity, alignment: .leading)
        if let description {
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 5)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    var description: LocalizedStringKey? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: title, description: description)
            content
        }
        .modifier(SettingsContainerModifier())
    }
}

struct StatusCapsuleLabel: View {
    let title: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(NSLocalizedString(title, comment: "Settings status"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct SettingsDetailRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(NSLocalizedString(title, comment: "Settings detail title"))
            Spacer()
            HStack { content }
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct SettingsMultiSelectList<Option: Identifiable & Equatable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: [Option]
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString(title, comment: "Settings list title"))
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.top, 8)

            ForEach(options) { option in
                Toggle(label(option), isOn: $selection.membership(of: option))
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}

struct ToggleRow: View {
    enum Style {
        case standard
        case compact
        case inset
    }

    let title: String
    var description: String = ""
    @Binding var isOn: Bool
    var style: Style = .standard

    var body: some View {
        let row = HStack(spacing: style == .compact ? 12 : nil) {
            SettingsRowLabel(title: title, description: description, titleFont: titleFont)
            Spacer(minLength: style == .compact ? 8 : nil)
            SettingsSwitch(title: title, isOn: $isOn)
        }
        switch style {
        case .standard:
            row.padding()
        case .compact:
            row.padding(.horizontal, 16).padding(.vertical, 9)
        case .inset:
            row.padding(.horizontal, 12).padding(.vertical, 7)
        }
    }

    private var titleFont: Font {
        switch style {
        case .standard: return .system(size: 14, weight: .medium)
        case .compact: return .system(size: 13, weight: .medium)
        case .inset: return .system(size: 13)
        }
    }
}

struct CompactToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        ToggleRow(title: title, description: description, isOn: $isOn, style: .compact)
    }
}

struct SwipeActionPickerRow<Action: Hashable & Identifiable>: View {
    let title: String
    let description: String
    @Binding var selection: Action
    let options: [Action]
    let label: (Action) -> String

    var body: some View {
        HStack {
            SettingsRowLabel(title: title, description: description)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .padding()
    }
}

struct LiquidGlassStylePickerRow: View {
    var title: String = "Liquid Glass Style"
    @Binding var selection: LiquidGlassMaterial

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowLabel(title: title, description: selection.summary)
            Spacer()
            HStack(spacing: 4) {
                stepButton(systemName: "chevron.left", help: "Previous Style", offset: -1)
                Picker("", selection: $selection) {
                    ForEach(LiquidGlassMaterial.allCases) { style in
                        Text(NSLocalizedString(style.displayName, comment: "Settings option")).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
                stepButton(systemName: "chevron.right", help: "Next Style", offset: 1)
            }
        }
        .padding()
    }

    private func stepButton(systemName: String, help: String, offset: Int) -> some View {
        Button {
            let styles = LiquidGlassMaterial.allCases
            let index = styles.firstIndex(of: selection) ?? 0
            selection = styles[(index + offset + styles.count) % styles.count]
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension Int {
    func formattedMinutes() -> String {
        let interval = TimeInterval(self * 60)
        return interval.formatted()
    }
}

struct IdentifiableInt: Identifiable {
    let id: Int
}
