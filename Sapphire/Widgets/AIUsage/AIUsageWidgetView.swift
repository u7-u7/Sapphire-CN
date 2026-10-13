import AppKit
import SwiftUI

@MainActor
struct AIUsageWidgetView: View {
    @ObservedObject private var service = AIUsageService.shared

    var body: some View {
        AIUsageCard(
            codex: service.codex,
            claude: service.claude,
            isRefreshing: service.isRefreshing,
            nextRefreshAt: service.nextRefreshAt,
            refresh: { service.refresh() }
        )
    }
}

struct AIUsageCard: View {
    let codex: AIUsageSnapshot
    let claude: AIUsageSnapshot
    let isRefreshing: Bool
    let nextRefreshAt: Date?
    let refresh: () -> Void

    @State private var showsDetails = false
    @State private var popoverOwner = UUID()
    @Environment(\.onNotchPopoverPresentationChange) private var reportPopoverPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            Button {
                let willPresent = !showsDetails
                // 先同步保留父组件，防止鼠标跨过弹窗间隙时已有收起任务抢先执行。
                reportPopoverPresentation(popoverOwner, willPresent)
                showsDetails = willPresent
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    MaterialMetricHeader(
                        title: AIUsageText.localize("AI Usage"),
                        status: status(at: now),
                        color: statusColor(at: now)
                    )
                    compactRow("Codex", snapshot: codex, tint: .mint, now: now)
                    compactRow("Claude", snapshot: claude, tint: .orange, now: now)
                    Text(syncSummary)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 260, alignment: .leading)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .contentShape(Rectangle())
            .help(AIUsageText.localize("Show usage windows and reset times"))
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                details(at: now)
            }
        }
        .onChange(of: showsDetails) { _, presented in
            // 外部点击或 Escape 也会改变 popover binding，释放临时保留。
            reportPopoverPresentation(popoverOwner, presented)
        }
        .onDisappear {
            reportPopoverPresentation(popoverOwner, false)
        }
    }

    private func compactRow(_ name: String, snapshot: AIUsageSnapshot, tint: Color, now: Date) -> some View {
        if !snapshot.balances.isEmpty || !snapshot.amounts.isEmpty {
            return AnyView(compactAmountRow(name, snapshot: snapshot, tint: tint, now: now))
        }
        let window = AIUsageText.primaryWindow(in: snapshot, now: now)
        let used = window.flatMap { AIUsageText.validUsedPercent($0, now: now) }
        return AnyView(VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(AIUsageText.providerName(name, snapshot: snapshot))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let window {
                    Text(AIUsageText.localize(window.title))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .frame(maxWidth: 48, alignment: .leading)
                        .layoutPriority(-1)
                }
                Text(AIUsageText.remaining(used))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(used.map { $0 >= 90 ? Color.orange : tint } ?? .white.opacity(0.55))
                    .fixedSize()
                Spacer(minLength: 3)
                Text(AIUsageText.resetCountdown(window?.resetAt, now: now))
                    .font(.system(size: 9, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    if let used {
                        Capsule()
                            .fill(tint.opacity(snapshot.isStale ? 0.45 : 0.85))
                            .frame(width: geometry.size.width * CGFloat((100 - used) / 100))
                    }
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine))
    }

    private func compactAmountRow(_ name: String, snapshot: AIUsageSnapshot, tint: Color, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(AIUsageText.providerName(name, snapshot: snapshot))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 3)
                Text(AIUsageText.compactAmount(in: snapshot, now: now))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(snapshot.isStale ? 0.55 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
            }
            Text(AIUsageText.amountResetSummary(in: snapshot, now: now))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
        .accessibilityElement(children: .combine)
    }

    private var syncSummary: String {
        let dates = [codex.updatedAt, claude.updatedAt].compactMap { $0 }
        guard let date = dates.min() else { return AIUsageText.localize("Never synced") }
        return String(format: AIUsageText.localize("Last sync %@"), AIUsageText.shortTime(date))
    }

    private func status(at now: Date) -> String {
        if isRefreshing { return AIUsageText.localize("Refreshing") }
        if codex.isStale || claude.isStale || hasExpiredWindow(at: now) {
            return AIUsageText.localize("Needs refresh")
        }
        if hasDisconnectedProvider { return AIUsageText.localize("Not connected") }
        if hasUnavailableReading(at: now) { return AIUsageText.localize("Usage unavailable") }
        return AIUsageText.localize("Synced")
    }

    private func statusColor(at now: Date) -> Color {
        if isRefreshing { return .cyan }
        if codex.isStale || claude.isStale || hasExpiredWindow(at: now) { return .orange }
        if hasDisconnectedProvider { return .white.opacity(0.55) }
        if hasUnavailableReading(at: now) { return .orange }
        return .mint
    }

    private func hasUnavailableReading(at now: Date) -> Bool {
        [codex, claude].contains { snapshot in
            if let message = snapshot.message, !message.isEmpty { return true }
            return !AIUsageText.hasAvailableReading(in: snapshot, now: now)
        }
    }

    private var hasDisconnectedProvider: Bool {
        [codex, claude].contains { $0.sourceName == nil && !AIUsageText.hasReportedItems(in: $0) }
    }

    private func hasExpiredWindow(at now: Date) -> Bool {
        [codex, claude].contains { snapshot in
            let resets = snapshot.windows.compactMap(\.resetAt)
                + snapshot.balances.compactMap(\.resetAt)
                + snapshot.amounts.compactMap(\.resetAt)
            return resets.contains { $0 <= now }
        }
    }

    func details(at now: Date) -> some View {
        ScrollView {
            detailContent(at: now)
        }
        .frame(width: 430, height: 520)
        .preferredColorScheme(.dark)
    }

    func detailContent(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AIUsageText.localize("AI Usage"))
                        .font(.title3.bold())
                    Text(AIUsageText.localize("Account usage and reset times"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: refresh) {
                    Label(
                        AIUsageText.localize(isRefreshing ? "Refreshing" : "Refresh now"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isRefreshing)
            }

            providerDetails("Codex", snapshot: codex, tint: .mint, command: "codex login", now: now)
            providerDetails("Claude", snapshot: claude, tint: .orange, command: "claude auth login", now: now)

            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(AIUsageText.localize("Next data refresh"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(nextRefreshAt.map { AIUsageText.fullTime($0) } ?? "—")
                    .monospacedDigit()
            }
            .font(.caption)
            Text(AIUsageText.localize("Reset times come from the provider. Data refresh only checks usage; it does not send a prompt."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .preferredColorScheme(.dark)
    }

    private func providerDetails(_ name: String, snapshot: AIUsageSnapshot, tint: Color, command: String, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AIUsageText.providerName(name, snapshot: snapshot)).font(.headline).foregroundStyle(tint)
                Spacer()
                if let plan = snapshot.plan, !plan.isEmpty {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !snapshot.balances.isEmpty {
                Text(AIUsageText.localize("Available balance"))
                    .font(.caption.weight(.semibold))
                ForEach(snapshot.balances) { balance in
                    balanceDetails(balance, now: now)
                }
            }
            ForEach(snapshot.amounts) { amount in
                amountDetails(amount, now: now)
            }
            ForEach(snapshot.windows) { window in
                windowDetails(window, now: now)
            }
            if !AIUsageText.hasReportedItems(in: snapshot) {
                Text(AIUsageText.localize("No usage reported"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = snapshot.message, !message.isEmpty {
                Text(AIUsageText.localize(message))
                    .font(.caption)
                    .foregroundStyle(snapshot.isStale ? .orange : .secondary)
                    .textSelection(.enabled)
            }
            if snapshot.isStale {
                Label(AIUsageText.localize("Showing previous data"), systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(AIUsageText.localize("Last successful sync"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.updatedAt.map { AIUsageText.fullTime($0) } ?? "—")
                    .monospacedDigit()
            }
            .font(.caption2)

            if snapshot.sourceName != nil || !snapshot.balances.isEmpty || !snapshot.amounts.isEmpty {
                Text(AIUsageText.localize("Configure the provider's usage URL and credentials in AI Usage settings. Refresh only checks usage."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AIUsageText.localize("Sign in with the CLI in Terminal, then refresh here."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Label(AIUsageText.localize("Copy command"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func balanceDetails(_ balance: AIUsageBalance, now: Date) -> some View {
        let isCurrent = AIUsageText.isCurrent(balance.resetAt, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(balance.currency).font(.caption.weight(.semibold))
            balanceAmount("Total available balance", amount: isCurrent ? balance.total : nil, currency: balance.currency)
            balanceAmount("Granted balance", amount: isCurrent ? balance.granted : nil, currency: balance.currency)
            balanceAmount("Topped-up balance", amount: isCurrent ? balance.toppedUp : nil, currency: balance.currency)
            resetDetails(balance.resetAt, now: now)
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func amountDetails(_ amount: AIUsageAmount, now: Date) -> some View {
        let isCurrent = AIUsageText.isCurrent(amount.resetAt, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(AIUsageText.localize(amount.title)).font(.caption.weight(.semibold))
            amountRow("Remaining quota", value: AIUsageText.remainingAmount(amount, now: now))
            amountRow("Used quota", value: AIUsageText.quantity(isCurrent ? amount.used : nil, unit: amount.unit))
            amountRow("Total quota", value: AIUsageText.quantity(isCurrent ? amount.total : nil, unit: amount.unit))
            resetDetails(amount.resetAt, now: now)
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func amountRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AIUsageText.localize(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func resetDetails(_ resetAt: Date?, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AIUsageText.localize("Resets at")).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(resetAt.map { AIUsageText.fullTime($0) } ?? "—")
                Text(resetAt.map { AIUsageText.resetCountdown($0, now: now) }
                    ?? AIUsageText.localize("Reset time not provided"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .monospacedDigit()
    }

    private func balanceAmount(_ title: String, amount: Decimal?, currency: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AIUsageText.localize(title)).foregroundStyle(.secondary)
            Spacer()
            Text(amount.map { AIUsageText.money($0, currency: currency) } ?? "—")
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func windowDetails(_ window: AIUsageWindow, now: Date) -> some View {
        let used = AIUsageText.validUsedPercent(window, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(AIUsageText.localize(window.title)).font(.caption.weight(.semibold))
            HStack {
                Text(String(format: AIUsageText.localize("Used %@"), AIUsageText.percent(used)))
                Spacer()
                Text(AIUsageText.remaining(used))
            }
            .font(.caption)
            .monospacedDigit()
            HStack(alignment: .firstTextBaseline) {
                Text(AIUsageText.localize("Resets at")).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(window.resetAt.map { AIUsageText.fullTime($0) } ?? "—")
                    Text(AIUsageText.resetCountdown(window.resetAt, now: now))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .monospacedDigit()
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum AIUsageText {
    static func localize(_ key: String) -> String {
        NSLocalizedString(key, comment: "AI account usage widget")
    }

    static func providerName(_ name: String, snapshot: AIUsageSnapshot) -> String {
        guard let source = snapshot.sourceName, !source.isEmpty else { return name }
        return "\(name) · \(source)"
    }

    static func hasReportedItems(in snapshot: AIUsageSnapshot) -> Bool {
        !snapshot.balances.isEmpty || !snapshot.amounts.isEmpty || !snapshot.windows.isEmpty
    }

    static func isCurrent(_ resetAt: Date?, now: Date) -> Bool {
        resetAt.map { $0 > now } ?? true
    }

    static func hasAvailableReading(in snapshot: AIUsageSnapshot, now: Date) -> Bool {
        snapshot.balances.contains { isCurrent($0.resetAt, now: now) }
            || snapshot.amounts.contains { amount in
                isCurrent(amount.resetAt, now: now)
                    && (amount.isUnlimited || amount.remaining != nil || amount.used != nil || amount.total != nil)
            }
            || snapshot.windows.contains { validUsedPercent($0, now: now) != nil }
    }

    static func compactAmount(in snapshot: AIUsageSnapshot, now: Date) -> String {
        if let balance = snapshot.balances.first {
            return isCurrent(balance.resetAt, now: now) ? money(balance.total, currency: balance.currency) : "—"
        }
        guard let amount = snapshot.amounts.first else { return "—" }
        return remainingAmount(amount, now: now)
    }

    static func remainingAmount(_ amount: AIUsageAmount, now: Date) -> String {
        guard isCurrent(amount.resetAt, now: now) else { return "—" }
        if amount.isUnlimited { return localize("Unlimited") }
        return quantity(amount.remaining, unit: amount.unit)
    }

    static func amountResetSummary(in snapshot: AIUsageSnapshot, now: Date) -> String {
        let resetAt: Date?
        if let balance = snapshot.balances.first { resetAt = balance.resetAt }
        else { resetAt = snapshot.amounts.first?.resetAt }
        return resetAt.map { resetCountdown($0, now: now) } ?? localize("Reset time not provided")
    }

    // 第三方单位由接口/配置决定；次数、token 和平台积分不能当成美元或百分比。
    static func quantity(_ amount: Decimal?, unit: String) -> String {
        guard let amount, !amount.isNaN else { return "—" }
        if ["CNY", "USD"].contains(unit.uppercased()) { return money(amount, currency: unit) }
        let value = NSDecimalNumber(decimal: amount).stringValue
        return unit.isEmpty ? value : "\(value) \(unit)"
    }

    static func money(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        // 余额可能小于一分，保留精度避免把非零金额渲染成零。
        formatter.maximumFractionDigits = 38
        formatter.roundingMode = .halfUp
        let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
        switch currency.uppercased() {
        case "CNY": return "¥\(value)"
        case "USD": return "$\(value)"
        default: return "\(currency) \(value)"
        }
    }

    static func validUsedPercent(_ window: AIUsageWindow, now: Date) -> Double? {
        if let resetAt = window.resetAt, resetAt <= now { return nil }
        guard let value = window.usedPercent, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    // Surface the tightest reported window, since either window may limit further work.
    static func primaryWindow(in snapshot: AIUsageSnapshot, now: Date) -> AIUsageWindow? {
        let valid = snapshot.windows.filter { validUsedPercent($0, now: now) != nil }
        return valid.max { ($0.usedPercent ?? 0) < ($1.usedPercent ?? 0) } ?? snapshot.windows.first
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value > 0 && value < 0.1 { return "<0.1%" }
        if value > 99.9 && value < 100 { return ">99.9%" }
        return String(format: value.rounded() == value ? "%.0f%%" : "%.1f%%", value)
    }

    static func remaining(_ used: Double?) -> String {
        String(format: localize("%@ left"), percent(used.map { 100 - $0 }))
    }

    static func resetCountdown(_ resetAt: Date?, now: Date) -> String {
        guard let resetAt else { return localize("Reset unknown") }
        let seconds = resetAt.timeIntervalSince(now)
        guard seconds > 0 else { return localize("Awaiting new window") }
        let minutes = Int(ceil(seconds / 60))
        let duration: String
        if minutes >= 24 * 60 {
            duration = String(format: localize("%dd %dh"), minutes / (24 * 60), minutes % (24 * 60) / 60)
        } else if minutes >= 60 {
            duration = String(format: localize("%dh %dm"), minutes / 60, minutes % 60)
        } else {
            duration = String(format: localize("%dm"), minutes)
        }
        return String(format: localize("Reset in %@"), duration)
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func fullTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

#if DEBUG
private struct AIUsageWidgetPreview: PreviewProvider {
    static var previews: some View {
        let now = Date()
        AIUsageCard(
            codex: AIUsageSnapshot(
                windows: [
                    AIUsageWindow(id: "primary", title: "5-hour window", usedPercent: 42, resetAt: now.addingTimeInterval(7_200)),
                    AIUsageWindow(id: "secondary", title: "Weekly window", usedPercent: 18, resetAt: now.addingTimeInterval(172_800))
                ],
                plan: "Plus", updatedAt: now, message: nil, isStale: false
            ),
            claude: AIUsageSnapshot(
                windows: [AIUsageWindow(id: "five_hour", title: "5-hour window", usedPercent: 73, resetAt: now.addingTimeInterval(5_100))],
                plan: nil, updatedAt: now, message: nil, isStale: false
            ),
            isRefreshing: false,
            nextRefreshAt: now.addingTimeInterval(300),
            refresh: {}
        )
        .padding(20)
        .background(.black)
    }
}
#endif
