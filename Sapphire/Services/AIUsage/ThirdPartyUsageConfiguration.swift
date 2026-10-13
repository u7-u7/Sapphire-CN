import Foundation

enum ThirdPartyUsageTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case deepSeek, sub2api, newAPI, custom
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .sub2api: return "Sub2API"
        case .newAPI: return "NewAPI"
        case .custom: return "自定义 JSON"
        }
    }
}

enum ThirdPartyUsageCredentialSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case currentCLI, separateQueryKey
    var id: String { rawValue }
    var displayName: String { self == .currentCLI ? "当前 CLI 的 API Key" : "独立查询密钥" }
}

enum ThirdPartyUsageAuthentication: String, CaseIterable, Identifiable, Codable, Sendable {
    case bearer, xApiKey, rawAuthorization, none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bearer: return "Bearer Token"
        case .xApiKey: return "X-API-Key"
        case .rawAuthorization: return "Authorization（原值）"
        case .none: return "无需认证"
        }
    }
}

enum ThirdPartyUsageResetFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case iso8601, unixSeconds, unixMilliseconds
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .iso8601: return "ISO 8601"
        case .unixSeconds: return "Unix 秒"
        case .unixMilliseconds: return "Unix 毫秒"
        }
    }
}

/// 可持久化的查询配置不包含密钥。独立查询密钥由既有 Keychain 管理器保存。
struct ThirdPartyUsageConfiguration: Codable, Equatable, Sendable {
    var enabled = false
    var platformName = ""
    var providerBaseURL = ""
    var queryURL = ""
    var template: ThirdPartyUsageTemplate = .custom
    var credentialSource: ThirdPartyUsageCredentialSource = .currentCLI
    var authentication: ThirdPartyUsageAuthentication = .bearer
    var userID = ""
    var remainingPath = ""
    var usedPath = ""
    var totalPath = ""
    var currencyPath = ""
    var unit = "USD"
    /// 服务端原始数值除以该值；NewAPI 的默认 quota 换算为 500000。
    var scale = "1"
    var resetPath = ""
    var resetFormat: ThirdPartyUsageResetFormat = .iso8601

    var displayName: String {
        let name = platformName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (template == .custom ? "第三方平台" : template.displayName) : name
    }

    mutating func applyTemplate(_ template: ThirdPartyUsageTemplate, baseURL: String) {
        self.template = template
        providerBaseURL = baseURL
        queryURL = Self.defaultQueryURL(template: template, baseURL: baseURL)
        remainingPath = ""; usedPath = ""; totalPath = ""; currencyPath = ""; resetPath = ""
        scale = "1"
        unit = "USD"
        authentication = .bearer
        credentialSource = .currentCLI
        resetFormat = .iso8601
        switch template {
        case .deepSeek:
            platformName = "DeepSeek"
            remainingPath = "balance_infos.0.total_balance"
            currencyPath = "balance_infos.0.currency"
        case .sub2api:
            platformName = "Sub2API"
            remainingPath = "remaining"; usedPath = "quota.used"; totalPath = "quota.limit"; currencyPath = "unit"
        case .newAPI:
            platformName = "NewAPI"
            remainingPath = "data.quota"; usedPath = "data.used_quota"
            scale = "500000"
            credentialSource = .separateQueryKey
        case .custom: break
        }
    }

    static func defaultQueryURL(template: ThirdPartyUsageTemplate, baseURL: String) -> String {
        guard template != .custom else { return "" }
        if template == .deepSeek { return "https://api.deepseek.com/user/balance" }
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/v1") { base.removeLast(3) }
        guard !base.isEmpty else { return "" }
        return base + (template == .newAPI ? "/api/user/self" : "/v1/usage")
    }
}
