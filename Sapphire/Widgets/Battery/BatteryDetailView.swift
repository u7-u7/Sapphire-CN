//
//  BatteryDetailView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-01

import SwiftUI

@MainActor
struct BatteryDetailView: View {
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var batteryEstimator: BatteryEstimator
    @StateObject private var stats = BatteryStatsViewModel()
    @State private var statsPollingRequester = "BatteryDetail-\(UUID().uuidString)"
    @State private var dragLimit: Double?
    @State private var chargeLimitMessage: String? = nil
    @State private var chargeLimitMessageTask: Task<Void, Never>?

    private var level: Double { min(max(Double(batteryEstimator.batteryLevel), 0), 100) / 100 }
    private var levelColor: Color {
        if stats.isCharging { return .green }
        if batteryEstimator.batteryLevel <= 20 { return .orange }
        return .mint
    }
    private var statusIcon: String {
        if statusIsPaused { return "pause.circle.fill" }
        if stats.isCharging { return "bolt.fill" }
        if stats.powerAdapterInfo != nil { return "powerplug.fill" }
        return "battery.100percent"
    }
    private var statusText: String {
        if statusIsPaused { return NSLocalizedString("Paused", comment: "Battery status") }
        if stats.isCharging { return NSLocalizedString("Charging", comment: "Battery status") }
        if stats.powerAdapterInfo != nil { return NSLocalizedString("Plugged in", comment: "Battery status") }
        return NSLocalizedString("Battery", comment: "Battery status")
    }
    private var statusColor: Color {
        if statusIsPaused { return .orange }
        if stats.isCharging { return .green }
        if stats.powerAdapterInfo != nil { return .cyan }
        return .mint
    }
    private var statusIsPaused: Bool {
        !stats.isCharging && stats.powerAdapterInfo != nil && batteryEstimator.batteryLevel < 100
    }

    // MARK: - Charge limit (drag the pill across the battery bar)

    private var chargeLimit: Int { settings.settings.batteryChargeLimit }
    private var displayedLimit: Double { dragLimit ?? Double(chargeLimit) }

    // MARK: - System Power hero (mirrors the Settings power hero card)

    private var power: SystemPowerReading {
        SystemPowerReading(
            systemLoad: stats.systemPower,
            adapterPower: stats.adapterPower,
            adapterConnected: (stats.powerAdapterInfo?.maxPower ?? 0) > 0,
            isCharging: stats.isCharging
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusAndBar
            HStack(alignment: .top, spacing: 10) {
                powerHero
                VStack(spacing: 10) {
                    compactMetric(title: "Battery Health", value: "\(stats.maxCapacityPercentage)%", icon: "heart.fill", color: .pink)
                    compactMetric(title: "Cycle Count", value: "\(stats.cycleCount)", icon: "arrow.triangle.2.circlepath", color: .purple)
                }
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .padding(.top, 4)
        .frame(width: 680, height: 310)
        .onAppear {
            stats.start()
            StatsManager.shared.setPolling(for: statsPollingRequester, requiredStats: [.systemPower, .batteryPower])
        }
        .onDisappear {
            stats.stop()
            StatsManager.shared.setPolling(for: statsPollingRequester, requiredStats: [])
            chargeLimitMessageTask?.cancel()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BATTERY")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(levelColor)
            Text("Power overview")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var statusAndBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let msg = chargeLimitMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(levelColor)
                        .transition(.opacity)
                } else {
                    Text("Charge limit \(chargeLimit)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .monospacedDigit()
                        .transition(.opacity)
                }
                Spacer()
                Text(stats.timeRemaining == "--" ? "No estimate" : stats.timeRemaining)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 8) {
                chargeLimitBar
                statPill(icon: "waveform.path.ecg", text: String(format: "%.2f V", stats.voltage / 1000.0), color: .blue)
                statPill(icon: "thermometer.medium", text: String(format: "%.1f°", stats.temperature), color: .orange)
                statusPill
            }
        }
    }

    private var chargeLimitBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let markerWidth: CGFloat = 3
            let markerX = max(markerWidth / 2, min(width - markerWidth / 2, width * CGFloat(displayedLimit) / 100))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(levelColor.gradient).frame(width: max(0, width * level))
                HStack(spacing: 3) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .bold))
                    Text("\(batteryEstimator.batteryLevel)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(.white.opacity(0.92))
                .padding(.leading, 10)
                Capsule()
                    .fill(Color.white)
                    .frame(width: markerWidth, height: 24)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
                    .scaleEffect(dragLimit == nil ? 1 : 1.3, anchor: .center)
                    .offset(x: markerX - markerWidth / 2)
                    .animation(dragLimit == nil ? .spring(response: 0.25, dampingFraction: 0.8) : nil, value: displayedLimit)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let fraction = g.location.x / max(width, 1)
                        dragLimit = min(100, max(50, (fraction * 100).rounded()))
                    }
                    .onEnded { _ in
                        if let limit = dragLimit {
                            settings.settings.batteryChargeLimit = Int(limit.rounded())
                            showChargeLimitMessage(Int(limit.rounded()))
                        }
                        dragLimit = nil
                    }
            )
            .help("Drag to set the charge limit — charging pauses at this level to help preserve battery health.")
        }
        .frame(height: 24)
    }

    private func statPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Color.white.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Image(systemName: statusIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(statusColor)
            Text(statusText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(statusColor.opacity(0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.55), lineWidth: 1))
    }

    private func showChargeLimitMessage(_ limit: Int) {
        chargeLimitMessageTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            chargeLimitMessage = "Charge limit changed to \(limit)%"
        }
        chargeLimitMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { chargeLimitMessage = nil }
            }
        }
    }

    private var powerHero: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("System Power")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(power.statusColor)
                        .frame(width: 6, height: 6)
                    Text(power.statusLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(power.statusColor)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(String(format: "%.2f", power.heroWatts))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("W")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
                Image(systemName: power.adapterConnected ? "powerplug.fill" : "battery.100")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(power.statusColor.opacity(0.85))
            }

            PowerSplitBar(reading: power)
                .frame(height: 6)

            HStack(spacing: 12) {
                if power.adapterConnected {
                    powerMetaChip(icon: "bolt.horizontal.fill", text: String(format: "Adapter %.0f W", power.adapterDisplayWatts))
                }
                powerMetaChip(icon: "laptopcomputer", text: String(format: "Draw %.2f W", power.systemLoad))
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func powerMetaChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(.white.opacity(0.72))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compactMetric(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}
