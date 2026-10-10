//
//  FocusWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import SwiftUI

struct FocusWidgetView: View {
    @EnvironmentObject private var focusManager: FocusSessionManager
    @EnvironmentObject private var settings: SettingsModel
    @Environment(\.navigationStack) private var navigationStack

    private var accent: Color { focusManager.isFocusBlock ? .green : .orange }
    private var accentColors: [Color] {
        focusManager.isFocusBlock ? [.green, .mint, .teal] : [.orange, .yellow, .pink]
    }

    private var phaseLabel: String {
        if focusManager.isPaused { return NSLocalizedString("PAUSED", comment: "Focus phase") }
        return focusManager.isFocusBlock ? NSLocalizedString("FOCUS", comment: "Focus phase") : NSLocalizedString("BREAK", comment: "Focus phase")
    }

    private var blockedCount: Int {
        guard focusManager.isBlockingActive else { return 0 }
        return settings.settings.focusBlockedApps.count + settings.settings.focusBlockedWebsites.count
    }

    var body: some View {
        Button {
            Task {
                try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                navigationStack.wrappedValue.append(NotchWidgetMode.focusSessionDetailView)
            }
        } label: {
            ZStack {
                HStack(alignment: .center, spacing: 10) {
                    primaryInfo.layoutPriority(1)
                    secondaryInfo
                }
                .padding(.horizontal, 10)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 200, minHeight: 90)
        .fixedSize()
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .animation(.default, value: focusManager.phase)
    }

    // MARK: - Primary readout

    @ViewBuilder
    private var primaryInfo: some View {
        HStack(spacing: 8) {
            if focusManager.isSessionActive {
                FocusWidgetTimerRing(
                    focusManager: focusManager,
                    accent: accent,
                    accentColors: accentColors
                )
            } else {
                Image(systemName: "moon.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(radius: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if focusManager.isSessionActive {
                        FocusWidgetCountdownText(focusManager: focusManager)
                    } else {
                        Text("Focus")
                    }
                }
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.4), value: focusManager.isSessionActive)

                Text(focusManager.isSessionActive ? phaseLabel : NSLocalizedString("Ready to focus", comment: "Focus widget status"))
                    .font(.headline).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(focusManager.isSessionActive ? accent : .secondary)

                Text(focusSummary)
                    .font(.subheadline).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: - Secondary stats (streak leads)

    private var secondaryInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            streakRow
            CompactInfoRow(iconName: "sun.max.fill", value: FocusSessionManager.format(focusManager.completedToday))
            CompactInfoRow(
                iconName: focusManager.isSessionActive ? "square.stack.3d.up.fill" : "checkmark.seal.fill",
                value: focusManager.isSessionActive
                    ? String(format: NSLocalizedString("%d blocks", comment: "Completed focus blocks"), focusManager.blocksCompletedThisSession)
                    : String(format: NSLocalizedString("%d sessions", comment: "Completed focus sessions"), focusManager.history.count)
            )
        }
        .animation(.easeInOut(duration: 0.4), value: focusManager.isSessionActive)
        .animation(.default, value: focusManager.currentStreak)
    }

    private var streakRow: some View {
        HStack(spacing: 5) {
            StreakFlame(size: 20, isActive: focusManager.currentStreak > 0)

            Text(streakText)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .id(streakText)
        .transition(.opacity)
    }

    private var streakText: String {
        let s = focusManager.currentStreak
        return String(format: NSLocalizedString("%d day streak", comment: "Consecutive focus days"), s)
    }

    private var focusSummary: String {
        if focusManager.isSessionActive {
            guard blockedCount > 0 else { return NSLocalizedString("No distractions blocked", comment: "Focus blocking status") }
            let key = blockedCount == 1 ? "Blocking %d distraction" : "Blocking %d distractions"
            return String(format: NSLocalizedString(key, comment: "Focus blocking status"), blockedCount)
        }
        return String(format: NSLocalizedString("%dm · %@ today", comment: "Focus duration and today's total"),
                      Int(settings.settings.focusSessionDuration / 60),
                      FocusSessionManager.format(focusManager.completedToday))
    }
}

@MainActor
private struct FocusWidgetTimerRing: View {
    let focusManager: FocusSessionManager
    let accent: Color
    let accentColors: [Color]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                ProgressRingView(
                    progress: focusManager.progress(at: context.date),
                    lineWidth: 4,
                    active: AngularGradient(colors: accentColors, center: .center)
                )
                Image(systemName: focusManager.isFocusBlock ? "figure.mind.and.body" : "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
            }
            .animation(.default, value: focusManager.remaining(at: context.date))
        }
        .frame(width: 44, height: 44)
        .shadow(color: accent.opacity(0.45), radius: 6)
    }
}

@MainActor
private struct FocusWidgetCountdownText: View {
    let focusManager: FocusSessionManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = focusManager.remaining(at: context.date)
            let label = FocusSessionManager.format(remaining)
            Text(label)
                .id(label)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: remaining)
        }
    }
}
