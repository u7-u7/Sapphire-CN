import Foundation

enum AIUsageProvider: String, CaseIterable, Identifiable, Sendable {
    case codex, claude
    var id: String { rawValue }
    var displayName: String { self == .codex ? "Codex" : "Claude" }
}

struct AIUsageWindow: Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double?
    let resetAt: Date?
}

struct AIUsageBalance: Identifiable, Sendable {
    let currency: String
    let total: Decimal
    let granted: Decimal?
    let toppedUp: Decimal?
    var resetAt: Date? = nil
    var id: String { currency }
}

struct AIUsageAmount: Identifiable, Sendable {
    let id: String
    let title: String
    let remaining: Decimal?
    let used: Decimal?
    let total: Decimal?
    let unit: String
    let resetAt: Date?
    var isUnlimited: Bool = false
}

struct AIUsageSnapshot: Sendable {
    var windows: [AIUsageWindow] = []
    var plan: String? = nil
    var updatedAt: Date? = nil
    var message: String? = "尚未刷新"
    var isStale: Bool = false
    var balances: [AIUsageBalance] = []
    var sourceName: String? = nil
    var amounts: [AIUsageAmount] = []

    func expiringWindows(at now: Date) -> Self {
        var result = self
        var expired = false
        result.windows = windows.map { window in
            guard let reset = window.resetAt, reset <= now, window.usedPercent != nil else { return window }
            expired = true
            return AIUsageWindow(id: window.id, title: window.title, usedPercent: nil, resetAt: reset)
        }
        result.balances = balances.filter { balance in
            guard let reset = balance.resetAt, reset <= now else { return true }
            expired = true
            return false
        }
        result.amounts = amounts.map { amount in
            guard let reset = amount.resetAt, reset <= now else { return amount }
            expired = true
            return AIUsageAmount(id: amount.id, title: amount.title, remaining: nil,
                used: nil, total: nil, unit: amount.unit, resetAt: reset)
        }
        if expired {
            result.isStale = true
            result.message = "额度窗口已重置，等待更新"
        }
        return result
    }

    static func retaining(_ prior: Self, for failure: AIUsageFailure, sameIdentity: Bool, at now: Date) -> Self {
        guard sameIdentity, !failure.clearsReading else {
            return Self(message: failure.message, isStale: false)
        }
        var result = prior.expiringWindows(at: now)
        result.message = failure.message
        result.isStale = result.updatedAt != nil
        return result
    }
}

enum AIUsageFailure: Error, Sendable {
    case missingCLI, authentication(AIUsageProvider), unsupportedClaudeConfiguration, deepSeekAuthentication, rateLimited, timeout, transport, invalidResponse, accountChanged
    case thirdPartyConfiguration(String), thirdPartyAuthentication(AIUsageProvider), thirdPartyEndpointChanged

    var clearsReading: Bool {
        switch self {
        case .authentication, .unsupportedClaudeConfiguration, .deepSeekAuthentication, .accountChanged, .missingCLI: return true
        case .thirdPartyConfiguration, .thirdPartyAuthentication, .thirdPartyEndpointChanged: return true
        default: return false
        }
    }

    var message: String {
        switch self {
        case .missingCLI: return "未找到 Codex CLI，请安装后运行 codex login"
        case .authentication(let provider):
            return provider == .codex ? "请运行 codex login 登录订阅账号" : "请运行 claude auth login 登录订阅账号"
        case .deepSeekAuthentication: return "DeepSeek 密钥不可用，请检查 Claude CLI 配置"
        case .unsupportedClaudeConfiguration: return "当前 Claude 使用自定义 API，无法读取官方订阅额度"
        case .rateLimited: return "服务暂时限流，15 分钟后重试"
        case .timeout: return "获取超时，稍后刷新"
        case .transport: return "暂时无法连接额度服务"
        case .invalidResponse: return "额度数据暂不可用，请更新 CLI 后重试"
        case .accountChanged: return "登录账号已变化，请稍后刷新"
        case .thirdPartyConfiguration(let message): return message
        case .thirdPartyAuthentication: return "查询凭据不可用，请检查额度查询设置"
        case .thirdPartyEndpointChanged: return "当前供应商与绑定的模型地址不一致，请更新额度查询设置"
        }
    }
}

struct AIUsageReadResult: Sendable {
    let identity: String?
    let snapshot: AIUsageSnapshot?
    let failure: AIUsageFailure?
    var sourceName: String? = nil
}

/// 手动刷新、自动轮询与重新启用组件共享请求门禁，避免绕过服务端限流。
struct AIUsageRequestGate: Sendable {
    private(set) var lastRequestAt: Date?
    private(set) var cooldownUntil: Date?
    static let minimumInterval: TimeInterval = 300
    static let cooldown: TimeInterval = 900

    func allowedAt(now: Date) -> Date {
        max(now, lastRequestAt?.addingTimeInterval(Self.minimumInterval) ?? now, cooldownUntil ?? now)
    }

    mutating func claim(at now: Date) -> Bool {
        guard allowedAt(now: now) <= now else { return false }
        lastRequestAt = now
        return true
    }

    mutating func record(_ failure: AIUsageFailure?, at now: Date) {
        if case .rateLimited? = failure { cooldownUntil = now.addingTimeInterval(Self.cooldown) }
    }
}

enum AIUsageParser {
    static func codex(_ result: [String: Any], plan: String?, at now: Date) -> AIUsageSnapshot {
        let buckets: [(String, [String: Any])]
        if let all = result["rateLimitsByLimitId"] as? [String: [String: Any]], !all.isEmpty {
            buckets = all.sorted { lhs, rhs in
                if lhs.key == "codex", rhs.key != "codex" { return true }
                if rhs.key == "codex", lhs.key != "codex" { return false }
                return lhs.key < rhs.key
            }
        } else if let single = result["rateLimits"] as? [String: Any] {
            buckets = [(single["limitId"] as? String ?? "codex", single)]
        } else { buckets = [] }
        var windows: [AIUsageWindow] = []
        for (key, bucket) in buckets {
            for slot in ["primary", "secondary"] {
                guard let value = bucket[slot] as? [String: Any] else { continue }
                let duration = finiteNumber(value["windowDurationMins"])
                let period = periodTitle(minutes: duration)
                let name = bucket["limitName"] as? String
                let prefix = key == "codex" ? nil : (name ?? key)
                windows.append(AIUsageWindow(id: "\(key).\(slot)",
                    title: prefix.map { "\($0) · \(period)" } ?? period,
                    usedPercent: percentage(value["usedPercent"]), resetAt: date(value["resetsAt"])))
            }
        }
        let bucketPlan = buckets.compactMap { $0.1["planType"] as? String }.first
        return AIUsageSnapshot(windows: windows, plan: bucketPlan ?? plan, updatedAt: now,
            message: windows.isEmpty ? "服务未返回订阅额度窗口" : nil)
    }

    // Percentage/reset parsing adapted from CodexIsland (MIT), UsageFetcher.swift.
    // https://github.com/ericjypark/codex-island/tree/d407c5e09c02978cb644cb21bc17fc6f636dd979
    static func claude(_ object: [String: Any], plan: String?, at now: Date) -> AIUsageSnapshot {
        let definitions = [("five_hour", "5 小时"), ("seven_day", "每周"),
                           ("seven_day_sonnet", "Sonnet · 每周"), ("seven_day_opus", "Opus · 每周")]
        let windows = definitions.compactMap { key, title -> AIUsageWindow? in
            guard let value = object[key] as? [String: Any] else { return nil }
            // utilization 本身就是百分数，0.5 是 0.5%，缺失绝不能替换为零。
            return AIUsageWindow(id: key, title: title,
                usedPercent: percentage(value["utilization"] ?? value["used_percent"]),
                resetAt: date(value["resets_at"]))
        }
        return AIUsageSnapshot(windows: windows, plan: plan, updatedAt: now,
            message: windows.isEmpty ? "服务未返回订阅额度窗口" : nil)
    }

    static func deepSeek(_ object: [String: Any], at now: Date) -> AIUsageSnapshot? {
        guard let items = object["balance_infos"] as? [[String: Any]] else { return nil }
        var seen: Set<String> = []
        let balances = items.compactMap { item -> AIUsageBalance? in
            guard let currency = item["currency"] as? String, ["CNY", "USD"].contains(currency),
                  let total = monetaryAmount(item["total_balance"]), seen.insert(currency).inserted else { return nil }
            return AIUsageBalance(currency: currency, total: total,
                granted: monetaryAmount(item["granted_balance"]), toppedUp: monetaryAmount(item["topped_up_balance"]))
        }
        guard !balances.isEmpty else { return nil }
        let insufficient = (object["is_available"] as? NSNumber).map {
            CFGetTypeID($0) == CFBooleanGetTypeID() && !$0.boolValue
        } ?? false
        return AIUsageSnapshot(updatedAt: now, message: insufficient ? "余额不足，请前往 DeepSeek 平台查看" : nil,
            balances: balances, sourceName: "DeepSeek")
    }

    /// 余额用十进制定点数；拒绝部分解析和超出 Decimal 精度的字符串，不能把缺失值变成零。
    static func monetaryAmount(_ value: Any?) -> Decimal? {
        guard let text = value as? String,
              text.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        let digits = text.filter { $0.isNumber }.drop(while: { $0 == "0" })
        guard digits.count <= 38, let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN else { return nil }
        return amount
    }

    static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    static func percentage(_ value: Any?) -> Double? {
        guard let value = finiteNumber(value), value >= 0 else { return nil }
        return min(100, value)
    }

    static func date(_ value: Any?) -> Date? {
        if let epoch = finiteNumber(value), epoch > 0, epoch <= 253402300799 { return Date(timeIntervalSince1970: epoch) }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func periodTitle(minutes: Double?) -> String {
        guard let minutes, minutes > 0, minutes <= 5_256_000 else { return "额度窗口" }
        if minutes == 10080 { return "每周" }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(Int(minutes / 1440)) 天" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60)) 小时" }
        return "\(Int(minutes)) 分钟"
    }
}
