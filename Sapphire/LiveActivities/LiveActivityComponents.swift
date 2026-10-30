//
//  LiveActivityComponents.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-06.
//

import SwiftUI
import EventKit
import AVFoundation

private func foregroundStyle(for state: ManagementState) -> AnyShapeStyle {
    switch state {
    case .inhibited:
        return AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
    case .calibrationStarted, .calibrating:
        return AnyShapeStyle(Color.purple)
    case .calibrationDone:
        return AnyShapeStyle(LinearGradient(colors: [.purple, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
    case .calibrationFailed:
        return AnyShapeStyle(LinearGradient(colors: [.cyan, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
    case .sailing:
        return AnyShapeStyle(Color.orange)
    case .dischargeStarted, .discharging, .dischargeStopped:
        return AnyShapeStyle(Color.cyan)
    case .heatProtectionOn, .heatProtection:
        return AnyShapeStyle(Color.red)
    case .heatProtectionOff:
        return AnyShapeStyle(Color.cyan)
    default:
        return AnyShapeStyle(Color.white.opacity(0.8))
    }
}

struct PersistentBatteryActivityView {
    static func left(for state: BatteryState, timeRemaining: String?, systemState: BatterySystemState) -> some View {
        let managementState = systemState.managementState

        return Group {
            if let timeString = timeRemaining, !timeString.isEmpty {
                Text(timeString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity.animation(.easeInOut))
            } else {
                let iconName: String = {
                    switch managementState {
                    case .inhibited: return "pause.fill"
                    case .sailing: return "sailboat.fill"
                    case .heatProtection: return "thermometer.sun.fill"
                    case .discharging: return "arrow.down.to.line.compact"
                    case .calibrating: return "battery.100.bolt"
                    case .charging: return state.isPluggedIn ? "bolt.fill" : "powerplug.fill"
                    default: return "info.circle"
                    }
                }()
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(foregroundStyle(for: managementState))
            }
        }
    }

    static func right(for state: BatteryState, systemState: BatterySystemState) -> some View {
        HStack(spacing: 6) {
            Text("\(state.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            FilledBatteryIcon(level: state.level, isCharging: state.isCharging, isPluggedIn: state.isPluggedIn, isLowBattery: state.isLow, managementState: systemState.managementState)
        }
    }
}

struct statsLiveActivityView {
    enum DisplayableStat: Identifiable, Hashable {
        case highLevel(StatType)
        case sensor(any Sensor_p)

        var id: String {
            switch self {
            case .highLevel(let type): return type.rawValue
            case .sensor(let sensor): return sensor.key
            }
        }

        static func == (lhs: statsLiveActivityView.DisplayableStat, rhs: statsLiveActivityView.DisplayableStat) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    static func left(for payload: StatsPayload, selectedStats: [StatType], selectedSensorKeys: [String]) -> some View {
        SideView(seed: payload, selectedStats: selectedStats, selectedSensorKeys: selectedSensorKeys, part: .icon)
    }

    static func right(for payload: StatsPayload, selectedStats: [StatType], selectedSensorKeys: [String]) -> some View {
        SideView(seed: payload, selectedStats: selectedStats, selectedSensorKeys: selectedSensorKeys, part: .value)
    }

    private struct SideView: View {
        let seed: StatsPayload
        let selectedStats: [StatType]
        let selectedSensorKeys: [String]
        let part: SingleStatPart
        @ObservedObject private var statsManager = StatsManager.shared

        private var payload: StatsPayload { statsManager.currentStats ?? seed }

        var body: some View {
            let allItems = getAllDisplayableItems(payload: payload, selectedStats: selectedStats, selectedSensorKeys: selectedSensorKeys)
            Group {
                if allItems.count == 1 {
                    singleStatView(for: allItems[0], payload: payload, part: part)
                } else {
                    let (leftItems, rightItems) = splitItems(allItems)
                    dynamicStatHStack(for: part == .icon ? leftItems : rightItems, payload: payload)
                }
            }
        }
    }

    private static func getAllDisplayableItems(payload: StatsPayload, selectedStats: [StatType], selectedSensorKeys: [String]) -> [DisplayableStat] {
        var items: [DisplayableStat] = []

        for statType in selectedStats {
            items.append(.highLevel(statType))
        }

        let availableSensors = payload.sensors?.sensors ?? []
        let selectedSensors = selectedSensorKeys.compactMap { key in
            availableSensors.first(where: { $0.key == key })
        }.sorted { $0.name < $1.name }

        for sensor in selectedSensors {
            items.append(.sensor(sensor))
        }

        return items
    }

    private static func splitItems(_ items: [DisplayableStat]) -> (left: [DisplayableStat], right: [DisplayableStat]) {
        let count = items.count
        guard count > 0 else { return ([], []) }

        let mid = (count + 1) / 2
        let left = Array(items.prefix(mid))
        let right = Array(items.suffix(from: mid))

        return (left, right)
    }

    @ViewBuilder
    private static func dynamicStatHStack(for items: [DisplayableStat], payload: StatsPayload) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                statItemView(for: item, payload: payload)
            }
        }
        .foregroundColor(.white.opacity(0.8))
        .animation(.easeInOut(duration: 0.4), value: payload)
    }

    @ViewBuilder
    private static func statItemView(for item: DisplayableStat, payload: StatsPayload) -> some View {
        switch item {
        case .highLevel(let statType):
            Group {
                if statType != .disk {
                    VStack(spacing: 1) {
                        Image(systemName: statType.systemImage)
                            .font(.system(size: 12, weight: .medium))

                        let value: Double = {
                            switch statType {
                            case .cpu: return payload.cpu?.totalUsage ?? 0
                            case .ram: return payload.ram?.usage ?? 0
                            case .gpu: return payload.gpu?.utilization ?? 0
                            case .systemPower: return payload.systemPower ?? 0
                            case .batteryPower: return payload.batteryPower ?? 0
                            default: return 0
                            }
                        }()

                        if statType == .systemPower || statType == .batteryPower {
                             Text(String(format: "%.1fW", value))
                                .contentTransition(.numericText())
                        } else {
                            Text("\(Int(value.isFinite ? (value * 100) : 0))%")
                                .contentTransition(.numericText())
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 45)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: statType.systemImage)
                            .font(.system(size: 12, weight: .medium))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.to.line.compact")
                                Text(Units(bytes: payload.disk?.activity.read ?? 0).getReadableSpeed(base: .byte))
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.to.line.compact")
                                Text(Units(bytes: payload.disk?.activity.write ?? 0).getReadableSpeed(base: .byte))
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }
            }

        case .sensor(let sensor):
            VStack(spacing: 1) {
                Text(sensor.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(sensor.formattedValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .frame(width: 55)
        }
    }

    enum SingleStatPart { case icon, value }
    @ViewBuilder
    private static func singleStatView(for item: DisplayableStat, payload: StatsPayload, part: SingleStatPart) -> some View {
        switch part {
        case .icon:
            let systemImage: String = {
                switch item {
                case .highLevel(let statType): return statType.systemImage
                case .sensor(let sensor):
                    switch sensor.type {
                    case .fan: return "fanblades.fill"
                    case .temperature: return "thermometer.medium"
                    case .voltage: return "bolt.circle"
                    case .current: return "bolt.horizontal.circle"
                    case .power, .energy: return "bolt.fill"
                    default: return "gauge.medium"
                    }
                }
            }()
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        case .value:
            let valueString: String = {
                switch item {
                case .highLevel(let statType):
                    switch statType {
                    case .cpu:
                        let usage = payload.cpu?.totalUsage ?? 0
                        return "\(Int(usage.isFinite ? usage * 100 : 0))%"
                    case .ram:
                        let usage = payload.ram?.usage ?? 0
                        return "\(Int(usage.isFinite ? usage * 100 : 0))%"
                    case .gpu:
                        let utilization = payload.gpu?.utilization ?? 0
                        return "\(Int(utilization.isFinite ? utilization * 100 : 0))%"
                    case .disk: return "\(Units(bytes: payload.disk?.activity.read ?? 0).getReadableSpeed(base: .byte)) R / \(Units(bytes: payload.disk?.activity.write ?? 0).getReadableSpeed(base: .byte)) W"
                    case .systemPower: return String(format: "%.1f W", payload.systemPower ?? 0)
                    case .batteryPower: return String(format: "%.1f W", payload.batteryPower ?? 0)
                    }
                case .sensor(let sensor):
                    return sensor.formattedValue
                }
            }()
            Text(valueString)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: valueString)
                .frame(minWidth: 50, alignment: .trailing)
        }
    }
}

struct FileProgressLiveActivityView {

    static func left(for task: FileTask) -> some View {
        let iconName: String
        switch task {
        case .universalTransfer(let transfer):
            switch transfer.sourceType {
            case .finder: iconName = "arrow.right.arrow.left.circle.fill"
            case .archiveExtraction: iconName = "archivebox.fill"
            case .dmgInstall: iconName = "externaldrive.fill.badge.plus"
            case .browserDownload, .manual: iconName = "arrow.down.circle.fill"
            }
        case .airDrop: iconName = "airplayaudio"
        case .incomingTransfer: iconName = "arrow.down.circle.fill"
        case .fileConversion: iconName = "arrow.triangle.2.circlepath"
        case .local: iconName = "doc.fill"
        }

        return ZStack {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 20, height: 20)
    }

    static func right(for task: FileTask) -> some View {
        let progress: Double?
        let fileName: String
        let statusText: String

        switch task {
        case .universalTransfer(let transferTask):
            progress = transferTask.progress
            fileName = transferTask.fileName
            let verb: String
            switch transferTask.sourceType {
            case .finder: verb = NSLocalizedString("Copying...", comment: "File transfer status")
            case .archiveExtraction: verb = NSLocalizedString("Extracting...", comment: "File transfer status")
            case .dmgInstall: verb = NSLocalizedString("Installing...", comment: "File transfer status")
            case .browserDownload, .manual: verb = NSLocalizedString("Downloading...", comment: "File transfer status")
            }
            if transferTask.sourceType == .finder {
                statusText = transferTask.speed > 0 ? TransferMetricsFormatter.speed(transferTask.speed) : verb
            } else if let progress {
                statusText = "\(Int(progress * 100))% • " + (transferTask.speed > 0 ? TransferMetricsFormatter.speed(transferTask.speed) : verb)
            } else {
                statusText = transferTask.speed > 0 ? TransferMetricsFormatter.speed(transferTask.speed) : verb
            }

        case .airDrop(let airDropTask):
            progress = airDropTask.progress
            fileName = airDropTask.fileName
            statusText = airDropTask.isComplete ? NSLocalizedString("Complete", comment: "File transfer status") : NSLocalizedString("Receiving...", comment: "File transfer status")
        case .incomingTransfer(let info):
            progress = info.progress
            fileName = info.fileDescription
            statusText = NSLocalizedString("Receiving...", comment: "File transfer status")
        case .fileConversion(let task):
            progress = task.progress
            fileName = task.fileName
            statusText = NSLocalizedString("Converting...", comment: "File transfer status")
        case .local(let item):
            progress = 1.0
            fileName = item.fileName
            statusText = NSLocalizedString("Ready", comment: "File transfer status")
        }

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            if let progressValue = progress {
                if progressValue >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    FileCircularProgressIndicator(progress: progressValue, size: 12, lineWidth: 3.0)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(width: 18, height: 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

}

struct IntelligenceAgentActivityView {
    static func left() -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.90, blue: 0.76), Color.pink.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    static func right(status: String, stepTitle: String, current: Int, total: Int) -> some View {
        let progress = total > 0 ? Double(current) / Double(total) : 0
        let label = stepTitle.isEmpty ? status : stepTitle

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if total > 0 {
                    Text("Step \(current) of \(total)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())
                } else if !status.isEmpty && status != label {
                    Text(status)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            if total > 0 {
                BlipStepProgressRing(progress: progress, current: current, total: total, size: 20, lineWidth: 5)
            }
        }
        .foregroundColor(.white.opacity(0.92))
    }
}

struct BlipStepProgressRing: View {
    let progress: Double
    let current: Int
    let total: Int
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ProgressRingView(
                progress: progress,
                lineWidth: lineWidth,
                active: AngularGradient(
                    colors: [
                        Color(red: 0.36, green: 0.90, blue: 0.76),
                        Color(red: 0.18, green: 0.62, blue: 0.55),
                        Color(red: 0.36, green: 0.90, blue: 0.76)
                    ],
                    center: .center
                )
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: progress)

            if total > 0 {
                Text("\(current)")
                    .font(.system(size: size * 0.38, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
    }
}

struct FileCircularProgressIndicator: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ProgressRingView(
            progress: progress,
            lineWidth: lineWidth,
            track: AnyShapeStyle(Color.accentColor.opacity(0.3)),
            active: Color.accentColor,
            rotation: .degrees(270)
        )
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.2), value: progress)
    }
}

struct AlbumArtView: View {
    @EnvironmentObject var musicWidget: MusicManager

    var body: some View {
        Group {
            if let image = (musicWidget.artwork ?? musicWidget.appIcon) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .id(musicWidget.currentTrackArtworkToken)
        .animation(nil, value: musicWidget.currentTrackArtworkToken)
        .onHover { isHovering in
            musicWidget.isHoveringAlbumArt = isHovering
        }
    }
}

struct QuickPeekView: View {
    let title: String
    let artist: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title + " · " + artist!)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(0.6)
        }
        .frame(maxWidth: 200)
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}

struct MusicUpNextView: View {
    let title: String
    let artist: String?
    let artworkURL: URL?

    @EnvironmentObject private var musicWidget: MusicManager

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("UP NEXT")
                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                .kerning(1.3)
                .foregroundColor(.gray.opacity(0.9))

            HStack(spacing: 7) {
                Group {
                    if let artworkURL {
                        CachedAsyncImage(url: artworkURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            placeholderArtwork
                        }
                    } else {
                        placeholderArtwork
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? "Unknown track" : title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 6)

                ProgressRingView(
                    progress: ringProgress,
                    lineWidth: 2.5,
                    active: Color.white
                )
                .animation(.linear(duration: 0.4), value: ringProgress)
                .frame(width: 16, height: 16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 0)
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }

    private var ringProgress: Double {
        guard musicWidget.totalDuration > 0 else { return 0.2 }
        let remaining = musicWidget.totalDuration - musicWidget.elapsedTime()
        guard remaining.isFinite && remaining >= 0 else { return 0 }
        let p = (10.0 - remaining) / 10.0
        return max(0.03, min(1.0, p))
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay(Image(systemName: "music.note")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.5)))
    }
}

struct MusicLyricsView: View {
    @EnvironmentObject var musicWidget: MusicManager
    @Binding var showLyrics: Bool

    @State private var lyricText: String?
    @State private var lyricID: UUID?

    init(_ showLyrics: Binding<Bool>) {
        self._showLyrics = showLyrics
    }

    var body: some View {
        Group {
            if let text = lyricText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(musicWidget.accentColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("lyric-\(lyricID?.uuidString ?? "")")
                    .onTapGesture {
                        showLyrics = true
                    }
            } else {
                EmptyView()
            }
        }
        .onAppear {
            let current = musicWidget.currentLyric
            self.lyricText = current?.translatedText ?? current?.text
            self.lyricID = current?.id
        }
        .onReceive(musicWidget.currentLyricPublisher) { newLyric in
            self.lyricText = newLyric?.translatedText ?? newLyric?.text
            self.lyricID = newLyric?.id
        }
    }
}

struct NowPlayingTextView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 200)
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            .opacity(1)
    }
}

// MARK: - Activity View Components

struct AudioSwitchActivityView {
    static func left(for event: AudioSwitchEvent) -> some View {
        Image(systemName: "arrow.uturn.backward.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for event: AudioSwitchEvent) -> some View {
        let targetDeviceIcon = event.direction == .switchedToMac ? "desktopcomputer" : "iphone"
        let targetDeviceName = event.direction == .switchedToMac ? "Mac" : "iPhone"

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Text("Connected to \(targetDeviceName)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Image(systemName: targetDeviceIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct CompactBatteryActivityView {
    static func left(for state: BatteryState, systemState: BatterySystemState) -> some View {
        let managementState = systemState.managementState

        let iconName: String = {
            switch managementState {
            case .inhibited: return "pause.fill"
            case .sailing: return "sailboat.fill"
            case .heatProtection, .heatProtectionOn: return "thermometer.sun.fill"
            case .heatProtectionOff: return "snowflake"
            case .discharging, .dischargeStarted: return "arrow.down.to.line.compact"
            case .dischargeStopped: return "checkmark"
            case .calibrating, .calibrationStarted: return "battery.100.bolt"
            case .calibrationDone: return "checkmark.seal.fill"
            case .calibrationFailed: return "exclamationmark.triangle.fill"
            case .charging: return state.isLow ? "battery.25" : "bolt.fill"
            }
        }()

        return Image(systemName: iconName)
            .frame(width: 20, height: 20)
            .foregroundStyle(foregroundStyle(for: managementState))
    }

    static func right(for state: BatteryState) -> some View {
        Text("\(state.level)%")
            .font(.system(size: 13, weight: .semibold))
    }
}

struct DefaultBatteryActivityView {
    static func left(for state: BatteryState, systemState: BatterySystemState) -> some View {
        let managementState = systemState.managementState

        let iconName: String
        let text: String
        let style: AnyShapeStyle

        switch managementState {
        case .charging:
            iconName = "bolt.fill"; text = "Charging"; style = AnyShapeStyle(Color.green)
        case .inhibited:
            iconName = "pause.fill"; text = "Charging Paused"; style = foregroundStyle(for: .inhibited)
        case .sailing:
            iconName = "sailboat.fill"; text = "Sailing by \(state.level)%"; style = foregroundStyle(for: .sailing)
        case .heatProtectionOn:
            iconName = "thermometer.sun.fill"; text = "Heat Protection On"; style = foregroundStyle(for: .heatProtectionOn)
        case .heatProtectionOff:
            iconName = "snowflake"; text = "Heat Protection Off"; style = AnyShapeStyle(Color.cyan)
        case .heatProtection:
            iconName = "thermometer.sun.fill"; text = "Heat Protection"; style = foregroundStyle(for: .heatProtection)
        case .dischargeStarted:
            iconName = "arrow.down.to.line.compact"; text = "Discharge Started"; style = foregroundStyle(for: .dischargeStarted)
        case .dischargeStopped:
            iconName = "checkmark"; text = "Discharge Stopped"; style = foregroundStyle(for: .dischargeStopped)
        case .discharging:
            iconName = "arrow.down.to.line.compact"; text = "Discharging"; style = foregroundStyle(for: .discharging)
        case .calibrationStarted:
            iconName = "battery.100.bolt"; text = "Calibration Started"; style = foregroundStyle(for: .calibrationStarted)
        case .calibrating:
            iconName = "battery.100.bolt"; text = "Calibrating"; style = foregroundStyle(for: .calibrating)
        case .calibrationDone:
            iconName = "checkmark.seal.fill"; text = "Calibration Complete"; style = foregroundStyle(for: .calibrationDone)
        case .calibrationFailed:
            iconName = "exclamationmark.triangle.fill"; text = "Calibration Failed"; style = foregroundStyle(for: .calibrationFailed)
        }

        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: iconName)
                Text(text)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(style)
        )
    }

    static func right(for state: BatteryState, timeRemaining: String?, systemState: BatterySystemState) -> some View {
        HStack(spacing: 6) {
            if SettingsModel.shared.settings.showEstimatedBatteryTime, let timeString = timeRemaining, !timeString.isEmpty {
                 Text(timeString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
            Text("\(state.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            FilledBatteryIcon(level: state.level, isCharging: state.isCharging, isPluggedIn: state.isPluggedIn, isLowBattery: state.isLow, managementState: systemState.managementState)
        }
    }
}

struct ReminderProximityActivityView {
    static func left() -> some View {
        Image(systemName: "checklist")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.orange)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(reminder: EKReminder) -> some View {
        let dueDate = reminder.dueDateComponents?.date
        return TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = dueDate?.timeIntervalSinceNow ?? 0
            Text(remaining.asRemainingClockOrNow)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct FilledBatteryIcon: View {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isLowBattery: Bool
    let managementState: ManagementState

    private let iconSize: CGFloat = 26
    private let iconWeight: Font.Weight = .regular

    private var iconName: String {
        if isCharging {
            switch managementState {
            case .calibrating, .calibrationStarted, .charging:
                return "battery.100.bolt"
            default:
                break
            }
        }

        switch level {
        case 96...100: return "battery.100"
        case 71...95:  return "battery.75"
        case 46...70:  return "battery.50"
        case 11...45:  return "battery.25"
        default:       return "battery.0"
        }
    }

    private var iconStyle: AnyShapeStyle {
        switch managementState {
        case .sailing:
            return AnyShapeStyle(Color.orange)
        case .heatProtection, .heatProtectionOn:
            return AnyShapeStyle(Color.red)
        case .discharging, .dischargeStarted:
            return AnyShapeStyle(Color.cyan)
        case .calibrating, .calibrationStarted:
            return AnyShapeStyle(Color.purple)
        case .inhibited:
            return AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .calibrationDone:
            return AnyShapeStyle(LinearGradient(colors: [.purple, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .calibrationFailed:
            return AnyShapeStyle(LinearGradient(colors: [.cyan, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
        default:
            if isCharging { return AnyShapeStyle(Color.green) }
            if isLowBattery { return AnyShapeStyle(Color.red) }
            return AnyShapeStyle(Color.white)
        }
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: iconSize, weight: iconWeight))
            .foregroundStyle(iconStyle)
            .frame(width: iconSize + 4, height: iconSize / 2 + 4)
            .animation(.easeInOut(duration: 0.3), value: iconName)
            .animation(.easeInOut(duration: 0.3), value: managementState)
            .padding(.leading, 4)
            .padding(.trailing, 7)
    }
}

struct BatteryRingView: View {
    let level: Int
    var color: Color?

    private var setColor: Color {
        if let unwrappedColor = color {
            return unwrappedColor
        } else {
            if level <= 10 {
                return .red
            } else if level <= 25 {
                return .yellow
            }
            return .green
        }
    }

    var body: some View {
        ProgressRingView(
            progress: Double(level) / 100.0,
            lineWidth: 3,
            track: AnyShapeStyle(Color.accentColor.opacity(0.3)),
            active: setColor
        )
        .animation(.easeOut, value: level)
        .frame(width: 14, height: 14)
        .padding(3)
    }
}

private extension BluetoothDeviceState {
    var liveActivityIconName: String {
        guard !iconName.isEmpty,
              NSImage(systemSymbolName: iconName, accessibilityDescription: nil) != nil else {
            return "bluetooth"
        }
        return iconName
    }
}

struct BluetoothConnectedPeripheralView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    static func right(for device: BluetoothDeviceState) -> some View {
        if SettingsModel.shared.settings.showBluetoothDeviceName {
            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                if let level = device.batteryLevel {
                    BatteryRingView(level: level)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        } else {
            if let level = device.batteryLevel {
                BatteryRingView(level: level)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
    }
}

struct BluetoothConnectedContinuityView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.blue)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for device: BluetoothDeviceState) -> some View {
        HStack(spacing: 6) {
            Text(device.name)
                 .font(.system(size: 13, weight: .semibold))
                 .foregroundColor(.white.opacity(0.9))
                 .lineLimit(1)
            Image(systemName: "link.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
        }
    }
}

struct BluetoothDisconnectedView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for device: BluetoothDeviceState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(device.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Text("Disconnected")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

struct BluetoothBatteryLowView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for device: BluetoothDeviceState) -> some View {
        HStack(spacing: 8) {
            if let level = device.batteryLevel {
                BatteryRingView(level: level)
                Text("\(level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
            } else {
                Text("Low Battery")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
    }
}

struct CalendarProximityActivityView {
    static func left() -> some View {
        Image(systemName: "calendar")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.blue)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(event: EKEvent) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = event.startDate.timeIntervalSinceNow
            Text(remaining.asRemainingClockOrNow)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct DesktopActivityView {
    static func left(for number: Int) -> some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
    }

    static func right(for number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
    }
}

struct EyeBreakFullActivityView: View {
    @EnvironmentObject var eyeBreakManager: EyeBreakManager
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var liveActivityManager: LiveActivityManager

    @State private var isShowing = false
    @State private var skipHovered = false
    @State private var doneHovered = false

    private var breakDuration: TimeInterval {
        TimeInterval(settings.settings.eyeBreakBreakDuration)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRingView(
                    progress: 1 - (eyeBreakManager.timeRemainingInBreak / breakDuration),
                    lineWidth: 6,
                    track: AnyShapeStyle(Color.white.opacity(0.15)),
                    active: Color.cyan
                )
                .animation(.linear(duration: 0.3), value: eyeBreakManager.timeRemainingInBreak)

                Image(systemName: "eye.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.cyan)
            }
            .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look Away")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Focus 20ft away.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        eyeBreakManager.dismissBreak()
                        liveActivityManager.dismissCurrentActivity()
                    } label: {
                        Text("Skip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EyeBreakPillButtonStyle(isProminent: false, isHovered: skipHovered))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            skipHovered = hovering
                        }
                    }

                    Button {
                        eyeBreakManager.completeBreak()
                        liveActivityManager.dismissCurrentActivity()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Done")
                            Text(String(format: "(%02d)", Int(eyeBreakManager.timeRemainingInBreak)))
                                .font(.system(.body, design: .monospaced))
                                .contentTransition(.numericText(countsDown: true))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EyeBreakPillButtonStyle(isProminent: true, isHovered: doneHovered))
                    .disabled(!eyeBreakManager.isDoneButtonEnabled)
                    .opacity(eyeBreakManager.isDoneButtonEnabled ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 0.3), value: eyeBreakManager.isDoneButtonEnabled)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            doneHovered = hovering && eyeBreakManager.isDoneButtonEnabled
                        }
                    }
                }
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 25)
        .padding(.top, NotchConfiguration.universalHeight)
        .frame(width: 380)
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.2)) {
                isShowing = true
            }
        }
    }
}

struct EyeBreakPillButtonStyle: ButtonStyle {
    var isProminent: Bool
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .background(backgroundColor(for: configuration))
            .foregroundColor(foregroundColor())
            .clipShape(Capsule())
            .shadow(color: isProminent && (isHovered || configuration.isPressed) ? .cyan.opacity(0.2) : .clear,
                    radius: 4, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.97 : isHovered ? 1.02 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15),
                       value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isHovered)
    }

    private func backgroundColor(for configuration: Configuration) -> Color {
        if isProminent {
            let baseColor: Color = .cyan
            if configuration.isPressed { return baseColor.opacity(0.6) }
            else if isHovered { return baseColor.opacity(0.9) }
            return baseColor
        }

        if configuration.isPressed { return .white.opacity(0.15) }
        else if isHovered { return .white.opacity(0.13) }
        return .white.opacity(0.1)
    }

    private func foregroundColor() -> Color {
        if isProminent { return .black }
        return .white
    }
}

struct UpdateAvailableActivityView {
    static func left() -> some View {
        Image(systemName: "square.and.arrow.down.badge.clock")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.cyan)
    }

    static func right(version: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Update Available")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            Text("Version \(version)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct UpdateAvailableWidgetView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared

    private var availableVersion: String? {
        if case .available(let version, _) = updateChecker.status {
            return version
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.badge.clock")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.cyan)

            VStack(spacing: 3) {
                Text("Update Available")
                    .font(.title3.bold())
                    .foregroundColor(.white.opacity(0.95))
                if let availableVersion {
                    Text("Version \(availableVersion) is ready to install.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How to update")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                stepRow(number: 1, text: "Open the About page in Settings")
                stepRow(number: 2, text: "Click \"Download Update\"")
                stepRow(number: 3, text: "Click \"Install and Relaunch\"")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: openAboutSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                    Text("Open About in Settings")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.cyan)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Text("Updates are installed from the About page in Sapphire's settings.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 380)
        .foregroundColor(.white)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 20, height: 20)
                .background(Color.cyan)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func openAboutSettings() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("SapphireSelectSection"),
                object: SettingsSection.about.rawValue
            )
        }
    }
}

struct FocusModeActivityView {

    private static let colorMap: [String: Color] = [
        "systemIndigoColor": .indigo,
        "systemPurpleColor": .purple,
        "systemTealColor": .teal,
        "systemBlueColor": .blue,
        "systemGreenColor": .green,
        "systemRedColor": .red,
        "systemOrangeColor": .orange,
        "systemYellowColor": .yellow,
        "systemPinkColor": .pink,
        "systemCyanColor": .cyan,
        "systemMintColor": .mint,
        "systemGrayColor": .gray
    ]

    private static let customImageAssetNames: Set<String> = [
        "rocket.fill",
        "apple.mindfulness",
        "person.lanyardcard.fill"
    ]

    private static func focusForegroundStyle(for mode: FocusModeInfo) -> AnyShapeStyle {
        if let gradientColorNames = mode.tintColorNames, gradientColorNames.count >= 2 {
            let gradientColors = gradientColorNames.compactMap { colorMap[$0] }
            if gradientColors.count >= 2 {
                return AnyShapeStyle(LinearGradient(gradient: Gradient(colors: gradientColors), startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }

        if let singleColorName = mode.tintColorName, let color = colorMap[singleColorName] {
            return AnyShapeStyle(color)
        }

        return AnyShapeStyle(Color.purple)
    }

    @ViewBuilder
    static func left(for mode: FocusModeInfo) -> some View {
        if mode.identifier == "com.apple.focus.reduce-interruptions" {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(focusForegroundStyle(for: mode))

        } else if customImageAssetNames.contains(mode.symbolName) {
            Image(mode.symbolName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(focusForegroundStyle(for: mode))
                .opacity(mode.isActive ? 1.0 : 0.7)

        } else {
            let finalSymbolName = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil) != nil ? mode.symbolName : "questionmark.circle.fill"

            Image(systemName: finalSymbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(focusForegroundStyle(for: mode))
        }
    }

    static func right(for mode: FocusModeInfo, displayMode: FocusDisplayMode) -> some View {
        let text: String

        if !mode.isActive {
            text = "Off"
        } else {
            switch displayMode {
            case .full:
                text = mode.name
            case .compact:
                text = "On"
            }
        }

        return Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(mode.isActive ? 0.9 : 0.7))
            .lineLimit(1)
    }
}

struct TimerActivityView {
    static func left(timerManager: TimerManager) -> some View {
        Image(systemName: timerManager.activeTimer == .stopwatch ? "stopwatch" : "timer")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(timerManager.activeTimer == .stopwatch ? .green : .orange)
            .frame(width: 25, height: 25)
    }

    static func right(timerManager: TimerManager) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let displayTime = timerManager.displayTime
            Text(displayTime.asStopwatchClock)
                .font(.system(size: 13, design: .monospaced).weight(.semibold))
                .contentTransition(.numericText(countsDown: timerManager.activeTimer == .system))
                .animation(.default, value: Int(displayTime))
        }
    }
}

struct TimerFinishedActivityView: View {
    @ObservedObject var timerManager: TimerManager
    let timerID: String

    private var timer: SapphireTimer? {
        timerManager.ringingTimers.first { $0.id == timerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: NotchConfiguration.initialSize.height)

            if let timer {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.18))
                            Image(systemName: "timer")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Timer")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(timer.label)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 18)

                        Text("00:00")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }

                    Button {
                        timerManager.dismissRingingTimer(id: timer.id)
                    } label: {
                        Label("Stop", systemImage: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .background(Color.orange.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss timer")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .frame(width: 360)
            }
        }
    }
}

struct WeatherActivityView {
    static func left(for data: ProcessedWeatherData) -> some View {
        Image(systemName: WeatherIconMapper.map(from: data.iconCode))
            .font(.title3)
            .symbolRenderingMode(.multicolor)
    }

    static func right(for data: ProcessedWeatherData) -> some View {
        RightView(data: data)
    }

    private struct RightView: View {
        let data: ProcessedWeatherData

        var body: some View {
            let temp = SettingsModel.shared.settings.weatherUseCelsius ? data.temperatureMetric : data.temperature
            Text("\(temp)°")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

struct ModernNotificationButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 0)
            .foregroundStyle(isPrimary ? .white : .primary.opacity(0.9))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct NotificationLiveActivityView: View {
    let payload: NotificationPayload

    @Binding var isHovered: Bool

    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var settings: SettingsModel
    @State private var replyText = ""
    @FocusState private var isTextFieldFocused: Bool

    @State private var contactImage: NSImage? = nil

    @State private var attachment: MessageAttachment? = nil
    @State private var isFetchingAttachment = false
    @State private var audioPlaybackState: AudioPlaybackState = .idle
    public enum AudioPlaybackState { case idle, playing, finished }

    @State private var didCopyCode = false

    private let iMessageManager = iMessageActionManager.shared

    private var isIMessage: Bool {
        return payload.appIdentifier == "com.apple.MobileSMS" || payload.appIdentifier == "com.apple.iChat"
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: NotchConfiguration.initialSize.height)

            if isIMessage {
                iMessageView
            } else {
                standardNotificationView
            }
        }
    }

    @ViewBuilder
    private var iMessageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    if let image = contactImage {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44).clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill").font(.system(size: 44))
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                    Image(systemName: "message.fill").font(.system(size: 10)).foregroundColor(.white)
                        .padding(4).background(Color.green).clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(payload.title).font(.headline).fontWeight(.bold)
                        Spacer()
                        Text("now").font(.caption).foregroundStyle(.secondary)
                    }
                    if !payload.hasAudioAttachment && !payload.hasImageAttachment {
                        Text(payload.body).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxHeight: 80)
            }
            .onTapGesture {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                notificationManager.dismissLatestNotification()
            }

            if isFetchingAttachment {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if let attachment = attachment {
                switch attachment.type {
                case .image:
                    CachedAsyncImage(url: attachment.localURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                case .audio:
                    AudioMessageView(attachment: attachment, playbackState: $audioPlaybackState)
                case .other:
                    Text("Attachment: \(attachment.localURL.lastPathComponent)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isHovered {
                replyBox.transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                actionButtons
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
        .frame(width: 400)
        .frame(minHeight: 120)
        .task(id: payload.id) {
            self.contactImage = await iMessageManager.fetchContactImage(forName: payload.title)
            attachment = nil; isFetchingAttachment = false; audioPlaybackState = .idle
            guard payload.hasAudioAttachment || payload.hasImageAttachment else { return }
            isFetchingAttachment = true
            self.attachment = await iMessageManager.fetchAndCopyLatestAttachment(for: payload.title)
            isFetchingAttachment = false
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.isHovered = hovering }
        }
        .onChange(of: isHovered) { _, newIsHovered in if !newIsHovered { isTextFieldFocused = false } }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if let appDelegate = NSApp.delegate as? AppDelegate {
                if isFocused { appDelegate.makeNotchWindowFocusable() } else { appDelegate.revertNotchWindowFocus() }
            }
        }
        .onDisappear { isHovered = false }
    }

    @ViewBuilder
    private var replyBox: some View {
        HStack(spacing: 8) {
            TextField("Reply...", text: $replyText)
                .textFieldStyle(.plain).onSubmit(sendIMessage).focused($isTextFieldFocused)
            Button(action: sendIMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3).symbolRenderingMode(.palette)
                    .foregroundStyle(replyText.isEmpty ? Color.secondary : Color.white, replyText.isEmpty ? Color.clear : Color.accentColor)
            }
            .buttonStyle(.plain).disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).frame(height: 40).background(.ultraThinMaterial).clipShape(Capsule())
    }

    @ViewBuilder
    private var standardNotificationView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let icon = payload.appIcon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.appName).font(.headline).fontWeight(.bold)
                    Text(payload.title + " - " + payload.body).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 100)
                Spacer()
            }
            .onTapGesture {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                notificationManager.dismissLatestNotification()
            }

            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(minWidth: 350, maxWidth: 420)
        .frame(minHeight: 120)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            standardActionButton(title: "Dismiss", systemName: "xmark") {
                notificationManager.dismissLatestNotification()
            }

            Spacer()

            if let code = payload.verificationCode, settings.settings.showCopyButtonForVerificationCodes {
                Button(action: {
                    NSPasteboard.general.copyString(code)
                    withAnimation(.spring) { didCopyCode = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.spring) { didCopyCode = false }
                        notificationManager.dismissLatestNotification()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        notificationManager.dismissLatestNotification()
                    }
                }) {
                    Label(
                        didCopyCode ? "Copied" : code,
                        systemImage: didCopyCode ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium, design: didCopyCode ? .default : .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .background(didCopyCode ? Color.green.opacity(0.25) : Color.primary.opacity(0.15))
                .foregroundStyle(didCopyCode ? .green : .primary)
                .clipShape(Capsule())
                .animation(.spring, value: didCopyCode)
            }

            if payload.appIdentifier == "com.apple.sharingd" {
                standardActionButton(title: "Show", systemName: "folder", isPrimary: true) {
                    if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) }
                    notificationManager.dismissLatestNotification()
                }
            } else {
                standardActionButton(title: "Open", systemName: "arrow.up.forward.app", isPrimary: true) {
                    NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                    notificationManager.dismissLatestNotification()
                }
            }
        }
    }

    private func sendIMessage() {
        let msg = replyText.trimmingCharacters(in: .whitespacesAndNewlines); guard !msg.isEmpty else { return }
        iMessageManager.sendMessage(msg, to: payload.title)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            replyText = ""; isTextFieldFocused = false; notificationManager.dismissLatestNotification()
        }
    }

    private func standardActionButton(title: String, systemName: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(isPrimary ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.15))
        .foregroundStyle(isPrimary ? .white : .primary)
        .clipShape(Capsule())
    }
}

struct AudioMessageView: View {
    let attachment: MessageAttachment
    @Binding var playbackState: NotificationLiveActivityView.AudioPlaybackState
    private var buttonLabel: String { switch playbackState { case .idle: "Play Audio Message"; case .playing: "Playing..."; case .finished: "Playback Finished" } }
    private var buttonIcon: String { switch playbackState { case .idle: "play.circle.fill"; case .playing: "stop.circle.fill"; case .finished: "checkmark.circle.fill" } }
    var body: some View {
        Button(action: { if playbackState == .idle { iMessageActionManager.shared.playAudio(at: attachment.localURL); playbackState = .playing } }) {
            HStack {
                Image(systemName: buttonIcon).font(.title2).symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor).contentTransition(.symbolEffect(.replace))
                Text(buttonLabel).font(.headline).fontWeight(.medium).foregroundStyle(.primary).contentTransition(.interpolate)
            }
            .padding(.horizontal, 16).frame(height: 50).frame(maxWidth: .infinity).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(playbackState != .idle).animation(.spring, value: playbackState)
    }
}

// MARK: - Lock Screen Auth Activity
private struct AnimatedLockIcon: View {
    @EnvironmentObject var lockScreenState: LockScreenState

    private var lockTint: Color {
        if lockScreenState.isUnlocked { return .white.opacity(0.8) }
        if lockScreenState.faceIDRequiresPassword { return .orange }
        return .white.opacity(0.8)
    }

    var body: some View {
        Image(systemName: lockScreenState.isUnlocked ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(lockTint)
            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
            .animation(.easeInOut(duration: 0.3), value: lockScreenState.faceIDRequiresPassword)
            .help(lockScreenState.faceIDRequiresPassword ? "Face ID locked — unlock with your password" : "")
    }
}

private struct LockScreenStatusIndicatorView: View {
    @EnvironmentObject var lockScreenState: LockScreenState

    var body: some View {
        let state = lockScreenState
        ZStack {
            if state.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale))
            } else {
                HStack(spacing: 8) {
                    if state.isCaffeineActive {
                        Image(systemName: "cup.and.heat.waves.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.opacity)
                    }

                    else if state.isAuthenticating, !state.faceIDRequiresPassword {
                        if state.isFaceIDEnabled {
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                        else if state.isBluetoothUnlockEnabled {
                            Image(systemName: "key.sensor.tag.radiowaves.left.and.right.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .transition(.opacity)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.isUnlocked)
        .animation(.easeInOut(duration: 0.3), value: state.faceIDRequiresPassword)
    }
}

struct LockScreenLiveActivityView {
    static func left() -> some View {
        AnimatedLockIcon()
    }

    static func right() -> some View {
        LockScreenStatusIndicatorView()
    }
}

struct PowerStateActivityView {
    static func left(for state: BatterySystemState) -> some View {
        let iconName: String
        let color: Color
        switch state.managementState {
        case .sailing:
            iconName = "sailboat.fill"
            color = .cyan
        case .heatProtection:
            iconName = "thermometer.sun.fill"
            color = .orange
        case .discharging:
            iconName = "arrow.down.to.line.compact"
            color = .yellow
        default:
            iconName = "info.circle.fill"
            color = .secondary
        }
        return Image(systemName: iconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(color)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for state: BatterySystemState, batteryLevel: Int) -> some View {
        HStack(spacing: 6) {
            Text(state.managementState.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 2) {
                Image(systemName: "battery.100")
                    .font(.caption)
                Text("\(batteryLevel)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .foregroundColor(.white.opacity(0.9))
    }
}

struct CalibrationActivityView: View {
    @EnvironmentObject var calibrationManager: CalibrationManager
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @State private var isShowing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.cyan)

                Text("Battery Calibration")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }

            Text(calibrationManager.state.description)
                .font(.callout)
                .foregroundColor(.secondary)
                .contentTransition(.interpolate)
                .animation(.easeInOut, value: calibrationManager.state)

            ProgressView(value: calibrationManager.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                .padding(.horizontal)
                .animation(.easeInOut, value: calibrationManager.progress)

            Button(action: {
                calibrationManager.cancel()
                liveActivityManager.dismissCurrentActivity()
            }) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 25)
        .padding(.top, NotchConfiguration.universalHeight)
        .frame(width: 380)
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.2)) {
                isShowing = true
            }
        }
    }
}

// MARK: - OTP / Parcel smart inbox live activities

struct OTPLiveActivityView: View {
    let event: OTPEvent
    var fromNotification: Bool = false

    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @State private var didCopy = false
    @State private var isShowing = false

    private var seedColor: Color { Color(red: 0.22, green: 0.68, blue: 0.58) }
    private var accentColor: Color { Color(red: 0.42, green: 0.84, blue: 0.72) }
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [seedColor, accentColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var digits: [String] {
        Array(event.code).map(String.init)
    }

    private var cellWidth: CGFloat {
        let available: CGFloat = 300
        let spacing: CGFloat = 8
        let totalSpacing = spacing * CGFloat(max(digits.count - 1, 0))
        return min(44, max(30, (available - totalSpacing) / CGFloat(digits.count)))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(seedColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "key.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(seedColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Verification code")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(event.title.isEmpty ? event.source : event.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    liveActivityManager.dismissCurrentActivity()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .roundedCard(fill: Color.white.opacity(0.06), cornerRadius: 16, stroke: Color.white.opacity(0.06))

            HStack(spacing: 8) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                    Text(digit)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: cellWidth, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(gradient)
                        )
                        .shadow(color: seedColor.opacity(0.35), radius: 8, y: 3)
                }
            }
            .scaleEffect(isShowing ? 1 : 0.85)
            .opacity(isShowing ? 1 : 0)

            if settings.settings.showCopyButtonForVerificationCodes {
                Button {
                    NSPasteboard.general.copyString(event.code)
                    withAnimation(.spring) { didCopy = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        // 新验证码可能已替换旧弹窗，旧的延迟回调不能关闭新活动。
                        guard liveActivityManager.currentActivity == .otp,
                              liveActivityManager.activityContent.id == AnyHashable(event.id) else { return }
                        liveActivityManager.dismissCurrentActivity()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        Text(didCopy ? "Copied" : "Copy code")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .background(didCopy ? seedColor.opacity(0.35) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(didCopy ? seedColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .padding(.top, NotchConfiguration.universalHeight)
        .frame(minWidth: 340, maxWidth: 400)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.25)) {
                isShowing = true
            }
            if settings.settings.autoCopyVerificationCodes {
                NSPasteboard.general.copyString(event.code)
                didCopy = true
            }
        }
    }
}

struct ParcelLiveActivityView: View {
    let parcel: ParcelShipment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parcel.carrier.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(parcel.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(parcel.status)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(parcel.isDelivered ? .green : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack {
                Text(parcel.trackingNumber)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let url = parcel.trackingURL {
                    Button("Track") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                }
            }

            if !parcel.detail.isEmpty {
                Text(parcel.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .padding(.top, NotchConfiguration.universalHeight)
        .frame(minWidth: 340, maxWidth: 440)
    }
}
