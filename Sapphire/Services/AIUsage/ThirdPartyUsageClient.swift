import Foundation
import CryptoKit

/// 两个 CLI 共用只读 GET 适配器；模板仅定义协议，不执行平台脚本。
enum ThirdPartyUsageClient {
    struct Credential: Sendable {
        let accessToken: String
        let configuredEndpoint: String
    }

    typealias Sender = (URLRequest) async throws -> (Data, HTTPURLResponse)

    static func fetch(provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration,
                      readCredential: () async -> Credential?, send: Sender = sendRequest) async -> AIUsageReadResult {
        let source = configuration.displayName
        guard let credential = await readCredential() else {
            return result(failure: .thirdPartyAuthentication(provider), source: source)
        }
        guard sameEndpoint(credential.configuredEndpoint, configuration.providerBaseURL) else {
            return result(failure: .thirdPartyEndpointChanged, source: source)
        }
        let identity = identity(provider: provider, configuration: configuration, credential: credential)
        let response: AIUsageReadResult
        do {
            let request = try makeRequest(configuration: configuration, credential: credential)
            let (data, http) = try await send(request)
            let snapshot = try parseResponse(data: data, status: http.statusCode, provider: provider,
                configuration: configuration, at: Date())
            response = AIUsageReadResult(identity: identity, snapshot: snapshot, failure: nil, sourceName: source)
        } catch let failure as AIUsageFailure {
            response = result(identity: identity, failure: failure, source: source)
        } catch {
            response = result(identity: identity,
                failure: (error as? URLError)?.code == .timedOut ? .timeout : .transport, source: source)
        }
        // 请求期间切换 endpoint 或 key 时丢弃旧读数；不重试另一个账户。
        let current = await readCredential()
        // 即使同时切换 key，429 也必须交给共用门禁记录，不能借账号变化绕过冷却。
        if case .rateLimited? = response.failure {
            return result(identity: current.map { self.identity(provider: provider, configuration: configuration, credential: $0) },
                failure: .rateLimited, source: source)
        }
        guard let current, sameEndpoint(current.configuredEndpoint, configuration.providerBaseURL),
              self.identity(provider: provider, configuration: configuration, credential: current) == identity else {
            return result(failure: .accountChanged, source: source)
        }
        return response
    }

    static func identity(provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration,
                         credential: Credential) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let serialized = (try? encoder.encode(configuration)) ?? Data()
        let binding = "\(provider.rawValue)|\(normalizedEndpoint(credential.configuredEndpoint))|\(credential.accessToken)|"
        return SHA256.hash(data: Data(binding.utf8) + serialized).map { String(format: "%02x", $0) }.joined()
    }

    static func sameEndpoint(_ current: String, _ bound: String) -> Bool {
        !bound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && normalizedEndpoint(current) == normalizedEndpoint(bound)
    }

    private static func normalizedEndpoint(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard var url = URLComponents(string: text) else { return text }
        url.scheme = url.scheme?.lowercased()
        url.host = url.host?.lowercased()
        return url.string ?? text
    }

    static func makeRequest(configuration: ThirdPartyUsageConfiguration, credential: Credential) throws -> URLRequest {
        let text = configuration.queryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.fragment == nil, let url = components.url else {
            throw AIUsageFailure.thirdPartyConfiguration("查询地址需要完整的 HTTPS URL，不能带用户名或密码")
        }
        guard decimal(configuration.scale).map({ $0 > 0 }) == true else {
            throw AIUsageFailure.thirdPartyConfiguration("换算除数需要大于 0")
        }
        let token = credential.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !configuration.userID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AIUsageFailure.thirdPartyConfiguration("认证信息包含无效字符")
        }
        if configuration.authentication != .none && token.isEmpty {
            throw AIUsageFailure.thirdPartyConfiguration("请配置查询密钥")
        }
        if configuration.template == .newAPI && configuration.userID.trimmingCharacters(in: .whitespaces).isEmpty {
            throw AIUsageFailure.thirdPartyConfiguration("NewAPI 需要账户 Access Token 和 User ID")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch configuration.authentication {
        case .bearer: request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .xApiKey: request.setValue(token, forHTTPHeaderField: "X-API-Key")
        case .rawAuthorization: request.setValue(token, forHTTPHeaderField: "Authorization")
        case .none: break
        }
        if configuration.template == .newAPI {
            request.setValue(configuration.userID, forHTTPHeaderField: "New-Api-User")
        }
        return request
    }

    private static func sendRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForResource = 25
        options.httpCookieStorage = nil
        options.httpShouldSetCookies = false
        options.urlCredentialStorage = nil
        let session = URLSession(configuration: options, delegate: AIUsageNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIUsageFailure.transport }
        return (data, http)
    }

    static func parseResponse(data: Data, status: Int, provider: AIUsageProvider,
                              configuration: ThirdPartyUsageConfiguration, at now: Date) throws -> AIUsageSnapshot {
        if status == 429 { throw AIUsageFailure.rateLimited }
        if status == 401 || status == 403 { throw AIUsageFailure.thirdPartyAuthentication(provider) }
        guard status == 200 else { throw AIUsageFailure.transport }
        guard data.count <= 2_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageFailure.invalidResponse
        }
        if let error = object["error"], !(error is NSNull) { throw AIUsageFailure.invalidResponse }
        let scale = decimal(configuration.scale)
        guard let scale, scale > 0 else { throw AIUsageFailure.thirdPartyConfiguration("换算除数需要大于 0") }
        switch configuration.template {
        case .deepSeek:
            guard var snapshot = AIUsageParser.deepSeek(object, at: now) else { throw AIUsageFailure.invalidResponse }
            let reset = resetDate(object, configuration: configuration)
            snapshot.balances = snapshot.balances.map { balance in
                AIUsageBalance(currency: balance.currency, total: balance.total / scale,
                    granted: balance.granted.map { $0 / scale }, toppedUp: balance.toppedUp.map { $0 / scale }, resetAt: reset)
            }
            snapshot.sourceName = configuration.displayName
            return snapshot
        case .newAPI:
            guard boolean(object["success"]) == true, object["data"] is [String: Any] else {
                throw AIUsageFailure.invalidResponse
            }
            return try mappedSnapshot(object, configuration: configuration, scale: scale, at: now)
        case .sub2api:
            guard boolean(object["isValid"]) != false else { throw AIUsageFailure.invalidResponse }
            return try sub2APISnapshot(object, configuration: configuration, scale: scale, at: now)
        case .custom:
            guard boolean(object["success"]) != false, boolean(object["isValid"]) != false else {
                throw AIUsageFailure.invalidResponse
            }
            return try mappedSnapshot(object, configuration: configuration, scale: scale, at: now)
        }
    }

    private static func mappedSnapshot(_ object: [String: Any], configuration: ThirdPartyUsageConfiguration,
                                       scale: Decimal, at now: Date) throws -> AIUsageSnapshot {
        let remaining = amount(object, path: configuration.remainingPath, scale: scale).flatMap {
            configuration.template == .sub2api && $0 < 0 ? nil : $0
        }
        let used = amount(object, path: configuration.usedPath, scale: scale).flatMap { $0 >= 0 ? $0 : nil }
        var limit = amount(object, path: configuration.totalPath, scale: scale).flatMap { $0 >= 0 ? $0 : nil }
        // NewAPI 的 quota 表示余额，used_quota 表示已用；不能把余额再次当总额度。
        if configuration.template == .newAPI, limit == nil, let remaining, let used { limit = remaining + used }
        guard remaining != nil || used != nil || limit != nil else { throw AIUsageFailure.invalidResponse }
        let amount = AIUsageAmount(id: "third-party", title: "额度", remaining: remaining, used: used, total: limit,
            unit: try currency(object, configuration: configuration), resetAt: resetDate(object, configuration: configuration))
        return AIUsageSnapshot(updatedAt: now, message: nil, sourceName: configuration.displayName, amounts: [amount])
    }

    private static func sub2APISnapshot(_ object: [String: Any], configuration: ThirdPartyUsageConfiguration,
                                        scale: Decimal, at now: Date) throws -> AIUsageSnapshot {
        if decimal(value(object, path: configuration.remainingPath)) == -1 {
            // -1 是协议的“不限量”，不能显示为欠费或伪造剩余额度。
            let reading = AIUsageAmount(id: "third-party", title: "额度", remaining: nil,
                used: amount(object, path: configuration.usedPath, scale: scale), total: nil,
                unit: try currency(object, configuration: configuration), resetAt: resetDate(object, configuration: configuration),
                isUnlimited: true)
            return AIUsageSnapshot(plan: object["planName"] as? String, updatedAt: now, message: nil,
                sourceName: configuration.displayName, amounts: [reading])
        }
        var config = configuration
        if value(object, path: config.currencyPath) == nil, let unit = value(object, path: "quota.unit") as? String {
            config.unit = unit
            config.currencyPath = ""
        }
        if let limit = amount(object, path: config.totalPath, scale: scale), limit <= 0 {
            config.usedPath = ""; config.totalPath = ""
        }
        var snapshot = try mappedSnapshot(object, configuration: config, scale: scale, at: now)
        snapshot.plan = object["planName"] as? String
        return snapshot
    }

    /// JSON 点路径只遍历对象和数组索引，不调用表达式或任意脚本。
    static func value(_ root: Any, path: String) -> Any? {
        guard !path.isEmpty else { return nil }
        let parts = path.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 24, !parts.contains(where: { $0.isEmpty }) else { return nil }
        var current: Any = root
        for part in parts {
            if let object = current as? [String: Any], let next = object[String(part)] { current = next }
            else if let array = current as? [Any], let index = Int(part), index >= 0, index < array.count { current = array[index] }
            else { return nil }
        }
        return current is NSNull ? nil : current
    }

    private static func amount(_ object: [String: Any], path: String, scale: Decimal) -> Decimal? {
        guard let amount = decimal(value(object, path: path)) else { return nil }
        let result = amount / scale
        return result.isNaN ? nil : result
    }

    static func decimal(_ value: Any?) -> Decimal? {
        if let text = value as? String { return AIUsageParser.monetaryAmount(text) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        // NSNumber 的规范文本可能带科学计数法（例如很小的 token 花费）；不先转成 Double。
        guard let amount = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN else { return nil }
        return amount
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func currency(_ object: [String: Any], configuration: ThirdPartyUsageConfiguration) throws -> String {
        let raw = (value(object, path: configuration.currencyPath) as? String) ?? configuration.unit
        let unit = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty, unit.count <= 24, unit.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw AIUsageFailure.thirdPartyConfiguration("请填写额度单位")
        }
        return unit
    }

    private static func resetDate(_ object: [String: Any], configuration: ThirdPartyUsageConfiguration) -> Date? {
        guard let raw = value(object, path: configuration.resetPath) else { return nil }
        if configuration.resetFormat == .iso8601 { return AIUsageParser.date(raw as? String) }
        guard let amount = decimal(raw) else { return nil }
        let seconds = NSDecimalNumber(decimal: amount).doubleValue / (configuration.resetFormat == .unixMilliseconds ? 1000 : 1)
        guard seconds.isFinite, seconds > 0, seconds <= 253402300799 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func result(identity: String? = nil, failure: AIUsageFailure, source: String) -> AIUsageReadResult {
        AIUsageReadResult(identity: identity, snapshot: nil, failure: failure, sourceName: source)
    }
}
