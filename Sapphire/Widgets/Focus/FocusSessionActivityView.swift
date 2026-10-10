//
//  FocusSessionActivityView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import SwiftUI

@MainActor
struct FocusSessionActivityView {
    static func left() -> some View {
        FocusSessionActivitySideView(side: .left)
    }

    static func right() -> some View {
        FocusSessionActivitySideView(side: .right)
    }
}

@MainActor
private struct FocusSessionActivitySideView: View {
    @ObservedObject private var focusManager = FocusSessionManager.shared
    let side: Side

    enum Side { case left, right }

    private var settings: Settings { SettingsModel.shared.settings }
    private var mode: FocusStatus { FocusModeManager.shared.currentStatus }
    private var showsTimeInsteadOfRing: Bool { settings.focusSessionLiveActivityShowTime }

    private var ringColors: [Color] {
        focusManager.isFocusBlock ? [.indigo, .purple, .blue] : [.orange, .yellow, .pink]
    }

    var body: some View {
        if side == .left {
            leftContent
        } else {
            rightContent
        }
    }

    // MARK: - Left: indigo moon

    private var leftContent: some View {
        ZStack {
            Image(systemName: "moon.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.95), Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Right: completing ring (or time)

    @ViewBuilder
    private var rightContent: some View {
        FocusSessionActivityClockView(
            focusManager: focusManager,
            showsTimeInsteadOfRing: showsTimeInsteadOfRing,
            ringColors: ringColors,
            mode: mode,
            displayMode: settings.focusDisplayMode
        )
    }
}

@MainActor
private struct FocusSessionActivityClockView: View {
    let focusManager: FocusSessionManager
    let showsTimeInsteadOfRing: Bool
    let ringColors: [Color]
    let mode: FocusStatus
    let displayMode: FocusDisplayMode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let remaining = focusManager.remaining(at: date)
        if showsTimeInsteadOfRing {
            VStack(alignment: .trailing, spacing: 0) {
                Text(FocusSessionManager.format(remaining))
                    .font(.system(size: 13, design: .monospaced).weight(.semibold))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: remaining)
                Text(subLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(subLabelColor)
            }
            .padding(.horizontal, 5)
        } else {
            let progress = max(0.001, focusManager.progress(at: date))
            ProgressRingView(
                progress: progress,
                lineWidth: 2.5,
                trackLineWidth: 5,
                track: AnyShapeStyle(Color.white.opacity(0.22)),
                active: AngularGradient(colors: ringColors, center: .center),
                clampsProgress: false
            )
            .animation(.linear(duration: 0.5), value: progress)
            .frame(width: 18, height: 18)
        }
    }

    private var subLabel: String {
        if mode.isActive {
            if displayMode == .compact { return NSLocalizedString("On", comment: "Focus mode status") }
            return NSLocalizedString(mode.name, comment: "Focus mode name")
        }
        return focusManager.isFocusBlock ? NSLocalizedString("Focus", comment: "Focus session phase") : NSLocalizedString("Break", comment: "Focus session phase")
    }

    private var subLabelColor: Color {
        if mode.isActive { return .white.opacity(0.85) }
        return focusManager.isFocusBlock ? Color.indigo : Color.orange
    }
}
