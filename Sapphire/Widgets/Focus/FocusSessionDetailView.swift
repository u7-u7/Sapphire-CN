//
//  FocusSessionDetailView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import SwiftUI

@MainActor
struct FocusSessionDetailView: View {
    @EnvironmentObject var focusManager: FocusSessionManager
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var ambient = FocusAmbientSoundManager.shared
    @Binding var navigationStack: [NotchWidgetMode]

    @State private var customMinutes: Double = 25
    @FocusState private var durationFieldFocused: Bool

    private var isCustomDuration: Bool { !presets.contains(customMinutes) }

    // MARK: - Muted Focus Palettes (Calm, non-stimulating tones)

    private var accent: Color {
        focusManager.isFocusBlock
            ? Color(red: 0.38, green: 0.85, blue: 0.65)
            : Color(red: 0.96, green: 0.68, blue: 0.44)
    }

    private let presets: [Double] = [15, 25, 45, 60]

    var body: some View {
        HStack(spacing: 20) {
            heroFocusStage
            companionPanel
        }
        .padding(16)
        .frame(width: 740, height: 360)
        .onAppear {
            customMinutes = settings.settings.focusSessionDuration / 60
        }
        .animation(.smooth(duration: 0.35), value: focusManager.phase)
    }

    // MARK: - Left Stage: Pure Focus (65% width)

    private var heroFocusStage: some View {
        VStack(spacing: 10) {

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Spacer(minLength: 0)

            timerRing

            if focusManager.isSessionActive, let endDate = focusManager.currentBlockEndDate {
                Text("ENDS \(endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(accent.opacity(0.8))
            } else {
                Text("ETA \(Date().addingTimeInterval(customMinutes * 60).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer(minLength: 0)

            primaryActionArea
        }
        .frame(maxWidth: .infinity)
    }

    private var timerRing: some View {
        FocusSessionTimerRing(focusManager: focusManager, accent: accent)
    }

    private var primaryActionArea: some View {
        VStack(spacing: 10) {
            if !focusManager.isSessionActive {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            customMinutes = minutes
                        } label: {
                            Text("\(Int(minutes))m")
                                .font(.system(size: 11, weight: customMinutes == minutes ? .bold : .medium))
                                .foregroundColor(customMinutes == minutes ? .white : .white.opacity(0.5))
                                .frame(width: 42, height: 26)
                                .background(
                                    customMinutes == minutes ? Color.white.opacity(0.12) : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Text("Custom")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isCustomDuration ? accent : .white.opacity(0.4))
                        TextField("Minutes", value: $customMinutes, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .focused($durationFieldFocused)
                            .lineLimit(1)
                            .frame(width: 52)
                            .onSubmit { durationFieldFocused = false }
                            .onChange(of: durationFieldFocused) { _, isFocused in
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    if isFocused { appDelegate.makeNotchWindowFocusable() } else { appDelegate.revertNotchWindowFocus() }
                                }
                            }
                            .onDisappear {
                                if durationFieldFocused { durationFieldFocused = false }
                            }
                        Text("min")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 10)
                    .background(
                        isCustomDuration || durationFieldFocused ? accent.opacity(0.12) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(durationFieldFocused ? accent.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }

                Button {
                    focusManager.startFocusSession(duration: customMinutes * 60)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Begin Focus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.05, green: 0.07, blue: 0.06))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Button {
                        focusManager.togglePause()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: focusManager.isPaused ? "play.fill" : "pause.fill")
                            Text(focusManager.isPaused ? "Resume" : "Pause")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if focusManager.isFocusBlock {
                        Button {
                            focusManager.postponeBreak()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("+5m Postpone")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Postpone the break by 5 minutes and keep focusing")
                    } else {
                        Button {
                            focusManager.skipBlock()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 44, height: 32)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Skip break")
                    }

                    Button {
                        focusManager.stopSession()
                    } label: {
                        Image(systemName: focusManager.canEndSessionEarly ? "stop.fill" : "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(focusManager.canEndSessionEarly ? .red.opacity(0.8) : .white.opacity(0.2))
                            .frame(width: 44, height: 32)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!focusManager.canEndSessionEarly)
                    .help(focusManager.canEndSessionEarly ? "End session early" : "Locked: strict mode active")
                }
            }
        }
        .frame(maxWidth: 320)
    }

    private var statusText: String {
        switch focusManager.phase {
        case .idle, .finished:
            return focusManager.phase == .finished ? NSLocalizedString("Session finished", comment: "Focus session status") : NSLocalizedString("Ready", comment: "Focus session status")
        case .focusing:
            return focusManager.isPaused ? NSLocalizedString("Paused", comment: "Focus session status") : String(format: NSLocalizedString("Block %d", comment: "Focus block number"), focusManager.currentBlockIndex + 1)
        case .onBreak:
            return focusManager.isPaused ? NSLocalizedString("Paused", comment: "Focus session status") : NSLocalizedString("Rest & recharge", comment: "Focus session status")
        }
    }

    // MARK: - Streak indicator

    private var snapshot: FocusStreakSnapshot { focusManager.streakSnapshot }

    private var streakIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StreakFlame(size: 18, isActive: snapshot.streak > 0)
                Text(snapshot.streak == 1 ? "1 day streak" : "\(snapshot.streak) day streak")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            FocusStreakWeekStrip(days: 7, showLetters: false)
                .environmentObject(focusManager)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Right Rail: Companion panel

    private var companionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            railHeader
            statsStrip
            streakIndicator
            ambientMiniPlayer
            environmentQuickToggles
            Spacer(minLength: 0)
        }
        .frame(width: 260, alignment: .top)
        .padding(.leading, 20)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var railHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SESSION CONTROL")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundColor(accent)
            Text("Stay in the zone")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 8) {
            statItem(label: "Focused", value: FocusSessionManager.format(focusManager.completedToday))
            Divider().frame(height: 20).opacity(0.15)
            statItem(label: "Blocks", value: "\(focusManager.blocksCompletedThisSession)")
            Divider().frame(height: 20).opacity(0.15)
            statItem(label: "Total", value: "\(focusManager.history.count)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private var ambientMiniPlayer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Ambiance", systemImage: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                if ambient.isPlaying {
                    Text("PLAYING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(accent)
                        .tracking(1)
                }
            }

            HStack(spacing: 8) {
                Button {
                    if !ambient.isPlaying {
                        ambient.start(type: settings.settings.focusAmbientSoundType, volume: settings.settings.focusAmbientSoundVolume)
                    } else {
                        ambient.stop()
                    }
                } label: {
                    Image(systemName: ambient.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(ambient.isPlaying ? accent.opacity(0.3) : Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(FocusAmbientSoundType.allCases) { type in
                        Button {
                            settings.settings.focusAmbientSoundType = type
                            if ambient.isPlaying { ambient.setType(type) }
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(settings.settings.focusAmbientSoundType.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Slider(value: Binding(
                    get: { ambient.volume },
                    set: {
                        ambient.volume = $0
                        settings.settings.focusAmbientSoundVolume = $0
                    }
                ), in: 0...1)
                .controlSize(.mini)
                .tint(accent)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var environmentQuickToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Environment Control")
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                quickToggleChip(
                    title: "Dim Apps",
                    icon: "moon.fill",
                    isOn: $settings.settings.focusDimInactiveApps
                )
                quickToggleChip(
                    title: "Mission Ctl",
                    icon: "rectangle.inset.filled",
                    isOn: $settings.settings.focusDisableDimInMissionControl
                )
                quickToggleChip(
                    title: "Hide Wall",
                    icon: "photo.fill",
                    isOn: $settings.settings.focusHideWallpaper
                )
                quickToggleChip(
                    title: "App Limit",
                    icon: "shield.fill",
                    isOn: $settings.settings.focusAppLimitEnabled
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func quickToggleChip(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(isOn.wrappedValue ? accent : .white.opacity(0.3))

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isOn.wrappedValue ? .white : .white.opacity(0.45))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Circle()
                    .fill(isOn.wrappedValue ? accent : Color.white.opacity(0.1))
                    .frame(width: 4, height: 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                isOn.wrappedValue ? accent.opacity(0.08) : Color.white.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isOn.wrappedValue ? accent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

}
@MainActor
private struct FocusSessionTimerRing: View {
    let focusManager: FocusSessionManager
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
    }

    private func content(at date: Date) -> some View {
        let remaining = focusManager.remaining(at: date)
        let progress = max(focusManager.progress(at: date), 0.001)

        return ZStack {
            ProgressRingView(
                progress: progress,
                lineWidth: 9,
                track: AnyShapeStyle(Color.white.opacity(0.05)),
                active: accent,
                clampsProgress: false,
                activeShadow: (accent.opacity(0.4), 12)
            )
            .animation(.smooth(duration: 0.2), value: progress)

            VStack(spacing: 5) {
                Text(FocusSessionManager.format(remaining))
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .monospacedDigit()
                    .animation(.smooth(duration: 0.2), value: remaining)

                if focusManager.isSessionActive {
                    Text("\(Int(progress * 100))% COMPLETE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(accent.opacity(0.8))
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.2), value: Int(progress * 100))
                } else {
                    Text("TAP START TO BEGIN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .frame(width: 170, height: 170)
    }
}
