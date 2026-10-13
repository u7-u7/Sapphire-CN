import Foundation

// Offline fixtures. Compile with AIUsageModels, ThirdPartyUsageConfiguration/Client,
// ClaudeUsageClient, DeepSeekUsageClient, and ProcessRunner. No real key reads or HTTP.
@main
struct VerifyThirdPartyUsage {
    static var checks = 0
    static let now = Date(timeIntervalSince1970: 1800000000)
    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }
        checks += 1
    }
    static func config(_ template: ThirdPartyUsageTemplate) -> ThirdPartyUsageConfiguration {
        var value = ThirdPartyUsageConfiguration()
        value.applyTemplate(template, baseURL: "https://fixture.invalid/v1/")
        value.enabled = true
        value.userID = "123"
        return value
    }
    static func parse(_ payload: String, _ config: ThirdPartyUsageConfiguration, status: Int = 200) throws -> AIUsageSnapshot {
        try ThirdPartyUsageClient.parseResponse(data: Data(payload.utf8), status: status,
            provider: .codex, configuration: config, at: now)
    }
    static func fails(_ payload: String, _ config: ThirdPartyUsageConfiguration, status: Int = 200) -> Bool {
        do { _ = try parse(payload, config, status: status); return false } catch { return true }
    }

    @MainActor
    static func main() async throws {
        try verifyTemplates()
        try verifyMappingAndDates()
        try verifyRequestPolicy()
        await verifyIdentityAndFailures()
        print("PASS: \(checks) third-party usage fixture checks; no key reads or real requests")
    }

    static func verifyTemplates() throws {
        let newAPI = config(.newAPI)
        expect(newAPI.queryURL == "https://fixture.invalid/api/user/self", "NewAPI endpoint removes trailing v1")
        expect(newAPI.credentialSource == .separateQueryKey, "NewAPI selects independent account token")
        let reading = try parse(#"{"success":true,"data":{"quota":1250000,"used_quota":750000}}"#, newAPI).amounts[0]
        expect(reading.remaining == Decimal(string: "2.5") && reading.used == Decimal(string: "1.5") && reading.total == 4,
            "NewAPI exact quota conversion and derived total")
        expect(fails(#"{"success":false,"data":{"quota":1250000}}"#, newAPI), "NewAPI failed body rejects data")
        var customScale = newAPI
        customScale.scale = "1000000"; customScale.unit = "CNY"
        let converted = try parse(#"{"success":true,"data":{"quota":"1250000"}}"#, customScale).amounts[0]
        expect(converted.remaining == Decimal(string: "1.25") && converted.unit == "CNY", "user-defined conversion is honored")
        let sub = config(.sub2api)
        expect(sub.queryURL == "https://fixture.invalid/v1/usage", "Sub2API does not duplicate v1")
        let unlimited = try parse(#"{"remaining":-1,"quota":{"used":20,"limit":0},"unit":"requests"}"#, sub).amounts[0]
        expect(unlimited.isUnlimited && unlimited.remaining == nil && unlimited.used == 20, "Sub2API -1 means unlimited")
        let noLimit = try parse(#"{"remaining":12,"quota":{"limit":0,"used":9,"unit":"CNY"}}"#, sub).amounts[0]
        expect(noLimit.remaining == 12 && noLimit.used == nil && noLimit.total == nil && noLimit.unit == "CNY",
            "Sub2API no quota limit never claims used or total")
        expect(fails(#"{"isValid":false,"remaining":12}"#, sub), "Sub2API invalid body rejects apparent amount")
        let deep = try parse(#"{"balance_infos":[{"currency":"CNY","total_balance":"384.92"},{"currency":"USD","total_balance":"0.01"}]}"#, config(.deepSeek))
        expect(deep.balances.count == 2 && deep.balances[0].total == Decimal(string: "384.92"), "DeepSeek preserves both currencies exactly")
        expect(deep.balances.allSatisfy { $0.resetAt == nil }, "DeepSeek never invents reset times")
    }

    static func verifyMappingAndDates() throws {
        var custom = config(.custom)
        custom.remainingPath = "accounts.0.left"; custom.usedPath = "accounts.0.used"
        custom.totalPath = "accounts.0.limit"; custom.currencyPath = "accounts.0.unit"
        custom.resetPath = "accounts.0.reset"; custom.resetFormat = .unixMilliseconds
        let reading = try parse(#"{"accounts":[{"left":"0.1000000000000000001","used":false,"limit":null,"unit":"tokens","reset":1800003600000}]}"#, custom).amounts[0]
        expect(reading.remaining == Decimal(string: "0.1000000000000000001"), "decimal strings do not round through double")
        expect(reading.used == nil && reading.total == nil && reading.unit == "tokens", "bool and null remain unknown")
        expect(reading.resetAt == now.addingTimeInterval(3600), "milliseconds convert to seconds")
        custom.resetFormat = .unixSeconds
        let seconds = try parse(#"{"accounts":[{"left":0,"reset":"1800003600"}]}"#, custom)
        expect(seconds.amounts[0].resetAt == now.addingTimeInterval(3600), "numeric string seconds parse")
        custom.resetFormat = .iso8601
        let iso = try parse(#"{"accounts":[{"left":0,"reset":"2027-01-15T08:30:00.000Z"}]}"#, custom)
        expect(iso.amounts[0].resetAt != nil, "ISO date parses")
        let usedOnly = try parse(#"{"accounts":[{"used":3}]}"#, custom)
        expect(usedOnly.amounts[0].remaining == nil, "used-only response never invents a balance")
        expect(fails(#"{"accounts":[{"left":false}]}"#, custom), "all missing/invalid numbers reject response")
        expect(fails(#"{"error":{"message":"fixture"},"accounts":[{"left":4}]}"#, custom), "error body cannot masquerade as balance")
        let nullError = try parse(#"{"error":null,"accounts":[{"left":4}]}"#, custom)
        expect(nullError.amounts[0].remaining == 4, "null error field does not reject valid reading")
        for bad in ["accounts.-1.left", "accounts.999.left", "accounts..left"] {
            custom.remainingPath = bad; custom.usedPath = ""; custom.totalPath = ""
            expect(fails(#"{"accounts":[{"left":4}]}"#, custom), "invalid JSON paths are safe")
        }
        expect(ThirdPartyUsageClient.decimal("NaN") == nil && ThirdPartyUsageClient.decimal(true) == nil,
            "non-money values are rejected")
        expect(ThirdPartyUsageClient.decimal(NSNumber(value: 0.0000001)) == Decimal(string: "0.0000001"), "small JSON numbers preserve exponent amounts")
    }

    static func verifyRequestPolicy() throws {
        var value = config(.newAPI)
        let credential = ThirdPartyUsageClient.Credential(accessToken: "fixture-query", configuredEndpoint: value.providerBaseURL)
        let request = try ThirdPartyUsageClient.makeRequest(configuration: value, credential: credential)
        expect(request.httpMethod == "GET" && request.timeoutInterval == 20, "read-only bounded request")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-query" && request.value(forHTTPHeaderField: "New-Api-User") == "123", "NewAPI account authentication headers")
        for auth in ThirdPartyUsageAuthentication.allCases {
            value.authentication = auth
            let request = try ThirdPartyUsageClient.makeRequest(configuration: value, credential: credential)
            expect(auth != .xApiKey || request.value(forHTTPHeaderField: "X-API-Key") == "fixture-query", "X-API-Key selectable")
            expect(auth != .rawAuthorization || request.value(forHTTPHeaderField: "Authorization") == "fixture-query", "raw authorization selectable")
            expect(auth != .none || request.value(forHTTPHeaderField: "Authorization") == nil, "none does not send token")
        }
        for bad in ["http://fixture.invalid/usage", "https://user:pass@fixture.invalid/usage", "https://fixture.invalid/#fragment", "garbage"] {
            value.queryURL = bad
            do { _ = try ThirdPartyUsageClient.makeRequest(configuration: value, credential: credential); expect(false, "unsafe URL rejected") }
            catch { expect(true, "unsafe URL rejected") }
        }
        value.queryURL = "https://fixture.invalid/usage"
        for bad in ["0", "-1", "NaN", "1.1suffix"] {
            value.scale = bad
            do { _ = try ThirdPartyUsageClient.makeRequest(configuration: value, credential: credential); expect(false, "invalid divisor rejected") }
            catch { expect(true, "invalid divisor rejected") }
        }
        value.scale = "1"
        let invalidHeader = ThirdPartyUsageClient.Credential(accessToken: "fixture\r\nInjected: value", configuredEndpoint: value.providerBaseURL)
        do { _ = try ThirdPartyUsageClient.makeRequest(configuration: value, credential: invalidHeader); expect(false, "header injection rejected") }
        catch { expect(true, "header injection rejected") }
        expect(ThirdPartyUsageClient.sameEndpoint("https://FIXTURE.invalid/v1/", "https://fixture.invalid/v1"), "endpoint comparison normalizes host and slash")
        expect(!ThirdPartyUsageClient.sameEndpoint("https://other.invalid", "https://fixture.invalid"), "endpoint changes break binding")
    }

    @MainActor
    static func verifyIdentityAndFailures() async {
        let value = config(.sub2api)
        var key = "fixture-query"
        var sent = 0
        let read = { ThirdPartyUsageClient.Credential(accessToken: key, configuredEndpoint: value.providerBaseURL) }
        let sender: ThirdPartyUsageClient.Sender = { request in
            sent += 1
            return (Data(#"{"remaining":12}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let good = await ThirdPartyUsageClient.fetch(provider: .claude, configuration: value, readCredential: read, send: sender)
        expect(good.snapshot?.amounts[0].remaining == 12 && sent == 1, "fetch uses injected sender once")
        let changed = await ThirdPartyUsageClient.fetch(provider: .claude, configuration: value, readCredential: read, send: { request in
            key = "fixture-new-query"; return try await sender(request)
        })
        if case .accountChanged? = changed.failure { expect(changed.snapshot == nil, "key switch drops old balance") }
        else { expect(false, "key switch detected") }
        let wrongEndpoint = await ThirdPartyUsageClient.fetch(provider: .claude, configuration: value,
            readCredential: { .init(accessToken: "fixture", configuredEndpoint: "https://other.invalid") }, send: sender)
        if case .thirdPartyEndpointChanged? = wrongEndpoint.failure { expect(sent == 2, "wrong endpoint sends no request") }
        else { expect(false, "wrong endpoint rejected") }
        for status in [429, 401, 403, 302, 500] {
            let failed = await ThirdPartyUsageClient.fetch(provider: .codex, configuration: value, readCredential: read, send: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            expect(failed.failure != nil && failed.snapshot == nil, "HTTP failure never yields a reading")
        }
        let timedOut = await ThirdPartyUsageClient.fetch(provider: .codex, configuration: value, readCredential: read,
            send: { _ in throw URLError(.timedOut) })
        if case .timeout? = timedOut.failure { expect(true, "timeout maps to bounded retry state") }
        else { expect(false, "timeout mapping") }
        let lateLimited = await ThirdPartyUsageClient.fetch(provider: .codex, configuration: value, readCredential: read, send: { request in
            key = "fixture-after-429"
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })
        if case .rateLimited? = lateLimited.failure { expect(true, "key rotation cannot erase 429 cooling") }
        else { expect(false, "late 429 preserved") }
        let credential = read()
        let original = ThirdPartyUsageClient.identity(provider: .codex, configuration: value, credential: credential)
        var changedConfig = value
        changedConfig.queryURL = "https://fixture.invalid/other-usage"
        expect(original != ThirdPartyUsageClient.identity(provider: .codex, configuration: changedConfig, credential: credential), "query URL changes identity")
        changedConfig = value; changedConfig.unit = "requests"
        expect(original != ThirdPartyUsageClient.identity(provider: .codex, configuration: changedConfig, credential: credential), "mapping changes cannot inherit stale amounts")
        expect(original != ThirdPartyUsageClient.identity(provider: .claude, configuration: value, credential: credential), "Codex and Claude do not share identity")
        let sentBeforeMissing = sent
        let missing = await ThirdPartyUsageClient.fetch(provider: .codex, configuration: value, readCredential: { nil }, send: sender)
        expect(missing.failure != nil && sent == sentBeforeMissing, "missing query credential never sends request")
    }
}
