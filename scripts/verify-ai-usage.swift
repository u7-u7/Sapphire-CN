import Foundation

// Compile this file with Services/AIUsage/*.swift and Services/System/ProcessRunner.swift.
// Every client invocation below uses a temporary fake executable or injected snapshots.
// No real credentials, provider endpoints, or model requests are used.
@main
struct VerifyAIUsage {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }
        checks += 1
    }

    static func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    @MainActor
    static func main() async throws {
        verifyParsing()
        verifyExpiryAndIdentity()
        verifyRequestGate()
        await verifyDeepSeekBalance()
        await verifyClaudeConfiguration()
        await verifyClaudeCredentialRotation()
        try await verifyCodexTransport()
        await verifyServiceLifecycle()
        await verifyLateRateLimitAndCancellation()
        print("PASS: \(checks) AI usage fixture checks; no credential reads or real provider requests")
    }

    static func verifyParsing() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let single = AIUsageParser.codex(json(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1800003600},"secondary":null}}"#), plan: "plus", at: now)
        expect(single.windows.count == 1, "weekly-only plans do not invent a five-hour quota")
        expect(single.windows[0].title == "每周", "Codex window label comes from duration")
        expect(single.windows[0].usedPercent == 0, "explicit zero remains a valid reading")
        expect(single.windows[0].resetAt == now.addingTimeInterval(3600), "reset timestamps use seconds")
        let multiple = AIUsageParser.codex(json(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":20,"windowDurationMins":60}},"codex":{"primary":{"usedPercent":30,"windowDurationMins":300},"secondary":{"usedPercent":false}}}}"#), plan: nil, at: now)
        expect(multiple.windows.count == 3, "all metered buckets are retained")
        expect(multiple.windows[0].usedPercent == 30, "multi-bucket data wins over legacy view")
        expect(multiple.windows[1].usedPercent == nil, "booleans are not zero/one percentages")
        expect(multiple.windows[2].title == "other · 1 小时", "other buckets remain identifiable")
        let unknown = AIUsageParser.codex(json(#"{"rateLimits":{"primary":{"windowDurationMins":1e100}}}"#), plan: nil, at: now)
        expect(unknown.windows[0].usedPercent == nil && unknown.windows[0].title == "额度窗口", "missing percentage and huge duration are safe")
        let claude = AIUsageParser.claude(json(#"{"five_hour":{"utilization":0.5,"resets_at":"2027-01-15T08:30:00.000Z"},"seven_day":{"utilization":null},"seven_day_sonnet":{"utilization":110}}"#), plan: "max", at: now)
        expect(claude.windows[0].usedPercent == 0.5, "0.5 utilization means 0.5 percent")
        expect(claude.windows[0].resetAt != nil, "fractional ISO reset dates parse")
        expect(claude.windows[1].usedPercent == nil, "null quota stays unknown")
        expect(claude.windows[2].usedPercent == 100, "over-quota gauges clamp safely")
        expect(AIUsageParser.claude([:], plan: nil, at: now).windows.isEmpty, "unknown response invents no windows")
        expect(AIUsageParser.percentage(-1) == nil, "negative usage is unknown")
        expect(AIUsageParser.date(1e100) == nil, "invalid epoch is not sent to countdown UI")
        if case .rateLimited? = ClaudeUsageClient.responseFailure(status: 200, data: Data(#"{"error":{"type":"rate_limit_error"}}"#.utf8)) {
            expect(true, "HTTP 200 error bodies still enforce cooldown")
        } else { expect(false, "HTTP 200 error bodies still enforce cooldown") }
        if case .authentication(.claude)? = ClaudeUsageClient.responseFailure(status: 403, data: Data()) {
            expect(true, "scope failures require login")
        } else { expect(false, "scope failures require login") }
        expect(ClaudeUsageClient.usesDefaultKeychain(environment: [:], home: "/fixture"), "default Claude config selects only default service")
        expect(!ClaudeUsageClient.usesDefaultKeychain(environment: ["CLAUDE_CONFIG_DIR": "/other"], home: "/fixture"), "custom config never borrows default-account credentials")
        expect(!ClaudeUsageClient.usesDefaultKeychain(environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/other"], home: "/fixture"), "custom secure-storage never borrows default credentials")
    }

    static func verifyExpiryAndIdentity() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let prior = AIUsageSnapshot(windows: [
            AIUsageWindow(id: "five", title: "5 小时", usedPercent: 35, resetAt: now.addingTimeInterval(10)),
            AIUsageWindow(id: "week", title: "每周", usedPercent: 60, resetAt: now.addingTimeInterval(1000))
        ], plan: "pro", updatedAt: now, message: nil)
        let stale = AIUsageSnapshot.retaining(prior, for: .transport, sameIdentity: true, at: now)
        expect(stale.isStale && stale.windows[0].usedPercent == 35, "same-account network failures mark prior readings stale")
        let changed = AIUsageSnapshot.retaining(prior, for: .transport, sameIdentity: false, at: now)
        expect(changed.windows.isEmpty && changed.updatedAt == nil, "new account never inherits quota")
        let expired = stale.expiringWindows(at: now.addingTimeInterval(10))
        expect(expired.windows[0].usedPercent == nil && expired.windows[1].usedPercent == 60, "passed reset invalidates only the affected window")
        let loggedOut = AIUsageSnapshot.retaining(prior, for: .authentication(.codex), sameIdentity: true, at: now)
        expect(loggedOut.windows.isEmpty, "auth failure clears all old readings")
        let unknown = AIUsageSnapshot()
        expect(unknown.windows.isEmpty && unknown.updatedAt == nil, "initial state cannot show fabricated zero")
    }

    static func verifyRequestGate() {
        var gate = AIUsageRequestGate()
        let now = Date(timeIntervalSince1970: 1800000000)
        expect(gate.claim(at: now), "first request is allowed")
        expect(!gate.claim(at: now.addingTimeInterval(299)), "manual retry cannot undercut five minutes")
        expect(gate.claim(at: now.addingTimeInterval(300)), "five-minute boundary is inclusive")
        gate.record(.rateLimited, at: now.addingTimeInterval(301))
        expect(!gate.claim(at: now.addingTimeInterval(1200)), "429 cooldown lasts fifteen minutes")
        expect(gate.claim(at: now.addingTimeInterval(1201)), "cooldown expiry allows next request")
    }

    static func verifyDeepSeekBalance() async {
        let now = Date(timeIntervalSince1970: 1800000000)
        let payload = json(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"384.92","granted_balance":"0.00","topped_up_balance":"384.92"},{"currency":"USD","total_balance":"12.0001"}]}"#)
        let snapshot = AIUsageParser.deepSeek(payload, at: now)!
        expect(snapshot.sourceName == "DeepSeek" && snapshot.windows.isEmpty, "API balances do not invent subscription windows or reset dates")
        expect(snapshot.balances.count == 2 && snapshot.balances[0].total == Decimal(string: "384.92"), "each API currency keeps exact Decimal precision")
        expect(snapshot.balances[1].granted == nil && snapshot.balances[1].toppedUp == nil, "missing breakdown remains unknown")
        expect(snapshot.balances[0].granted == 0 && snapshot.message == nil, "explicit zero remains a genuine balance")
        let zero = AIUsageParser.deepSeek(json(#"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0.00"},{"currency":"USD","total_balance":"-0.25"}]}"#), at: now)!
        expect(zero.balances[0].total == 0 && zero.balances[1].total == Decimal(string: "-0.25"), "zero and negative balances remain real amounts")
        expect(zero.message?.contains("余额不足") == true, "is_available false shows balance-insufficient guidance")
        let invalid = json(#"{"balance_infos":[{"currency":"EUR","total_balance":"10"},{"currency":"CNY"},{"currency":"CNY","total_balance":12}]}"#)
        expect(AIUsageParser.deepSeek(invalid, at: now) == nil, "unknown currencies and missing or numeric totals invent no money")
        expect(AIUsageParser.deepSeek([:], at: now) == nil, "absent balance response cannot succeed")
        let duplicate = AIUsageParser.deepSeek(json(#"{"balance_infos":[{"currency":"CNY","total_balance":"1.00"},{"currency":"CNY","total_balance":"2.00"}]}"#), at: now)!
        expect(duplicate.balances.count == 1 && duplicate.balances[0].total == 1, "duplicate currency is not summed or assigned duplicate UI identity")
        for invalid in ["1.2junk", "NaN", "1e5", " 1.0", "001", String(repeating: "9", count: 39)] {
            expect(AIUsageParser.monetaryAmount(invalid) == nil, "strict Decimal parsing rejects malformed or overprecision amount")
        }
        let base = ["ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic", "ANTHROPIC_AUTH_TOKEN": "fixture-deepseek"]
        let credential = DeepSeekUsageClient.credential(environment: base)!
        expect(credential.identity == DeepSeekUsageClient.credential(environment: base)?.identity, "same endpoint and credential have stable in-memory identity")
        for bad in ["http://api.deepseek.com/anthropic", "https://api.deepseek.com.evil.invalid/anthropic", "https://evil.invalid@api.deepseek.com/anthropic", "https://api.deepseek.com:443/anthropic", "https://api.deepseek.com/other", "https://api.deepseek.com/anthropic?key=fixture", "https://api.deepseek.com/anthropic#fragment"] {
            expect(DeepSeekUsageClient.credential(environment: ["ANTHROPIC_BASE_URL": bad, "ANTHROPIC_AUTH_TOKEN": "fixture"]) == nil, "factory never sends credentials outside the exact trusted DeepSeek endpoint")
        }
        expect(DeepSeekUsageClient.credential(environment: ["ANTHROPIC_BASE_URL": base["ANTHROPIC_BASE_URL"]!]) == nil, "missing provider credential never starts a request")
        expect(DeepSeekUsageClient.isConfigured(environment: ["ANTHROPIC_BASE_URL": base["ANTHROPIC_BASE_URL"]!]), "selected DeepSeek provider never falls back to another subscription when its key is absent")
        let missingKey = await DeepSeekUsageClient.fetch(readCredential: { nil }, request: { _ in fatalError("Missing API key must not issue a request") })
        if case .deepSeekAuthentication? = missingKey.failure {
            expect(missingKey.sourceName == "DeepSeek", "missing provider key gives its own authentication guidance")
        } else { expect(false, "missing provider key gives its own authentication guidance") }

        expect(DeepSeekUsageClient.credential(environment: ["ANTHROPIC_BASE_URL": base["ANTHROPIC_BASE_URL"]!, "ANTHROPIC_API_KEY": "fixture-api-key"]) != nil, "API key source supports the same trusted destination")
        let replacement = DeepSeekUsageClient.Credential(accessToken: "fixture-new", configuredEndpoint: credential.configuredEndpoint)
        expect(credential.identity != replacement.identity, "token rotation changes balance identity")
        expect(credential.identity != DeepSeekUsageClient.Credential(accessToken: credential.accessToken, configuredEndpoint: "https://provider.example.invalid").identity, "endpoint switch changes balance identity")
        let successful = await DeepSeekUsageClient.fetch(readCredential: { credential }, request: { selected in
            AIUsageReadResult(identity: selected.identity, snapshot: snapshot, failure: nil)
        })
        expect(successful.snapshot?.balances.count == 2 && successful.failure == nil && successful.sourceName == "DeepSeek", "injected balance request carries provider metadata without network")
        var reads = 0
        let switched = await DeepSeekUsageClient.fetch(readCredential: {
            reads += 1; return reads == 1 ? credential : replacement
        }, request: { selected in AIUsageReadResult(identity: selected.identity, snapshot: snapshot, failure: nil) })
        if case .accountChanged? = switched.failure { expect(switched.snapshot == nil, "changed credential discards in-flight balances") }
        else { expect(false, "changed credential discards in-flight balances") }
        let initialFailure = await DeepSeekUsageClient.fetch(readCredential: { credential }, request: { selected in
            AIUsageReadResult(identity: selected.identity, snapshot: nil, failure: .transport)
        })
        expect(initialFailure.sourceName == "DeepSeek" && initialFailure.snapshot == nil, "first provider failure keeps its source label without a success snapshot")
        reads = 0
        let limited = await DeepSeekUsageClient.fetch(readCredential: {
            reads += 1; return reads == 1 ? credential : replacement
        }, request: { selected in AIUsageReadResult(identity: selected.identity, snapshot: nil, failure: .rateLimited) })
        if case .rateLimited? = limited.failure {
            expect(limited.identity == replacement.identity && limited.snapshot == nil, "late provider 429 keeps cooldown while credentials rotate")
        } else { expect(false, "late provider 429 keeps cooldown while credentials rotate") }
        let stale = AIUsageSnapshot.retaining(snapshot, for: .transport, sameIdentity: true, at: now)
        expect(stale.balances.count == 2 && stale.isStale && stale.sourceName == "DeepSeek", "same-identity network failure retains old balance as stale")
        expect(AIUsageSnapshot.retaining(snapshot, for: .transport, sameIdentity: false, at: now).balances.isEmpty, "provider switch cannot inherit another balance")
        expect(AIUsageSnapshot.retaining(snapshot, for: .deepSeekAuthentication, sameIdentity: true, at: now).balances.isEmpty, "invalid provider credential clears old balances")
    }

    static func verifyClaudeConfiguration() async {
        func custom(_ environment: [String: String] = [:], _ settings: String? = nil) -> Bool {
            ClaudeUsageClient.hasUnsupportedConfiguration(environment: environment, settingsData: settings.map { Data($0.utf8) })
        }
        expect(!custom(), "absent API configuration keeps the subscription-login guidance")
        expect(!custom(["ANTHROPIC_BASE_URL": "https://api.anthropic.com"]), "official endpoint alone is not a custom API")
        expect(custom(["ANTHROPIC_BASE_URL": "https://provider.example.invalid"]), "custom process endpoint is unsupported")
        expect(custom([:], #"{"env":{"ANTHROPIC_BASE_URL":"https://provider.example.invalid","ANTHROPIC_AUTH_TOKEN":"fixture"}}"#), "settings API configuration is detected without token output")
        expect(custom(["ANTHROPIC_AUTH_TOKEN": "fixture"]), "API auth token cannot supply subscription quota")
        expect(custom(["ANTHROPIC_API_KEY": "fixture"]), "API key cannot supply subscription quota")
        expect(!custom([:], "invalid json"), "malformed settings do not fabricate configuration")
        expect(!custom([:], #"{"env":["invalid"]}"#), "malformed env safely keeps login guidance")
        expect(custom([:], #"{"env":{"ANTHROPIC_BASE_URL":"https://provider.example.invalid","IGNORED":42}}"#), "unrelated non-string env preserves the endpoint decision")
        expect(custom(["ANTHROPIC_BASE_URL": "not a url"]), "invalid endpoint is not mistaken for the official service")
        expect(!custom(["ANTHROPIC_BASE_URL": "https://provider.example.invalid"], #"{"env":{"ANTHROPIC_BASE_URL":"https://API.ANTHROPIC.COM"}}"#), "CLI settings override shell environment and official host is case insensitive")
        expect(!custom(["ANTHROPIC_AUTH_TOKEN": "  "]), "blank auth configuration is not a credential")
        let missing = await ClaudeUsageClient.fetch(readCredential: { nil }, request: { _ in
            fatalError("Missing subscription credential must not issue a request")
        }, unsupportedConfiguration: { true })
        if case .unsupportedClaudeConfiguration? = missing.failure {
            expect(true, "missing OAuth with custom API gives an actionable unsupported state")
        } else { expect(false, "missing OAuth with custom API gives an actionable unsupported state") }
        let valid = ClaudeUsageClient.Credential(accessToken: "fixture-valid", plan: nil, expiresAt: nil)
        let supported = await ClaudeUsageClient.fetch(readCredential: { valid }, request: { credential in
            AIUsageReadResult(identity: credential.identity, snapshot: AIUsageSnapshot(), failure: nil)
        }, unsupportedConfiguration: { fatalError("Valid OAuth must retain its existing read path") })
        expect(supported.failure == nil, "valid subscription OAuth takes precedence over API configuration")
        let prior = AIUsageSnapshot(windows: [AIUsageWindow(id: "old", title: "5 小时", usedPercent: 10, resetAt: nil)], updatedAt: Date())
        expect(AIUsageSnapshot.retaining(prior, for: .unsupportedClaudeConfiguration, sameIdentity: true, at: Date()).windows.isEmpty, "unsupported configuration clears stale subscription readings")
    }

    static func verifyClaudeCredentialRotation() async {
        let rotated = ClaudeFixture(failure: .authentication(.claude))
        let result = await ClaudeUsageClient.fetch(readCredential: { await rotated.credential() }, request: { await rotated.request($0) })
        let attempts = await rotated.attempts
        expect(attempts == 2 && result.snapshot?.windows.first?.usedPercent == 0.5, "401 rereads the current store and retries a rotated token once")
        let limited = ClaudeFixture(failure: .rateLimited)
        let throttled = await ClaudeUsageClient.fetch(readCredential: { await limited.credential() }, request: { await limited.request($0) })
        let limitedAttempts = await limited.attempts
        let currentIdentity = await limited.currentIdentity
        if case .rateLimited? = throttled.failure { expect(true, "429 stays a cooldown after login changes") }
        else { expect(false, "429 stays a cooldown after login changes") }
        expect(limitedAttempts == 1 && throttled.identity == currentIdentity, "429 never retries another token and old-account reading cannot carry forward")
        let expired = ClaudeUsageClient.Credential(accessToken: "fixture-expired", plan: nil, expiresAt: Date(timeIntervalSince1970: 1))
        let expiredResult = await ClaudeUsageClient.fetch(readCredential: { expired }, request: { _ in fatalError("Expired credential must not be sent") })
        expect(expiredResult.snapshot == nil, "expired credential never issues a request")
    }

    static func verifyCodexTransport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-ai-usage-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        while IFS= read -r packet; do
          case "$packet" in
            *'"initialize"'*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *'"initialized"'*) : ;;
            *'"account/read"'*)
              case "$packet" in
                *'"id":1'*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"fixture@example.invalid","planType":"pro"}}}' ;;
                *) printf '%s\\n' '{"id":3,"result":{"account":{"type":"chatgpt","email":"fixture@example.invalid","planType":"pro"}}}' ;;
              esac ;;
            *'"account/rateLimits/read"'*) printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":22,"windowDurationMins":10080,"resetsAt":2100000000}}}}' ;;
            *) exit 7 ;;
          esac
        done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let result = await CodexUsageClient.fetch(executablePath: executable.path, fingerprint: { "fixture-account" }, timeout: 3)
        expect(result.snapshot?.windows.first?.usedPercent == 22 && result.failure == nil, "official RPC handshake and queries parse without a turn")
        expect(result.snapshot?.plan == "pro" && result.identity != nil, "RPC account metadata scopes the reading")
        // 子进程仍存活但已关闭 stdin，不能对宿主进程产生致命 SIGPIPE。
        try Data("#!/bin/sh\nIFS= read -r packet\nexec 0<&-\nprintf '%s\\n' '{\"id\":0,\"result\":{}}'\nexec /bin/sleep 10\n".utf8).write(to: executable)
        let closed = await CodexUsageClient.fetch(executablePath: executable.path, fingerprint: { "fixture" }, timeout: 1)
        expect(closed.snapshot == nil && closed.failure != nil, "closed child stdin reports failure instead of killing host")
        // 假进程不读 stdin，不输出数据；超时必须结束且不遗留阻塞的主线程。
        try Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: executable)
        let started = Date()
        let timed = await CodexUsageClient.fetch(executablePath: executable.path, fingerprint: { "fixture" }, timeout: 0.1)
        if case .timeout? = timed.failure { expect(true, "silent child process times out") }
        else { expect(false, "silent child process times out") }
        expect(Date().timeIntervalSince(started) < 3, "timeout terminates child promptly")
    }

    @MainActor
    static func verifyServiceLifecycle() async {
        let reads = FixtureReads()
        let service = AIUsageService(fetchCodex: { await reads.read(.codex) }, fetchClaude: { await reads.read(.claude) })
        service.configure(enabled: true, refreshMinutes: 5)
        for _ in 0..<10 { service.configure(enabled: true, refreshMinutes: 5); service.refresh() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let counts = await reads.counts
        expect(counts[.codex] == 1 && counts[.claude] == 1, "global refresh deduplicates repeated configure and manual clicks")
        expect(!service.isRefreshing && service.codex.windows.first?.usedPercent == 40, "published snapshot receives injected result")
        expect(service.nextRefreshAt != nil, "automatic polling remains armed outside view lifecycle")
        service.stop()
        expect(service.nextRefreshAt == nil && !service.isRefreshing, "disabling stops polling")
        service.configure(enabled: true, refreshMinutes: 5)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let after = await reads.counts
        expect(after[.codex] == 1 && after[.claude] == 1, "disable-enable does not bypass request gates")
        service.stop()
    }

    @MainActor
    static func verifyLateRateLimitAndCancellation() async {
        let reads = DelayedFixtureReads()
        let service = AIUsageService(fetchCodex: { await reads.read(.codex) }, fetchClaude: { await reads.read(.claude) })
        service.configure(enabled: false, refreshMinutes: 30)
        expect(!service.isRefreshing && service.nextRefreshAt == nil, "disabled configure never starts work")
        service.configure(enabled: true, refreshMinutes: 5)
        try? await Task.sleep(nanoseconds: 30_000_000)
        service.stop()
        await reads.finish(failure: .rateLimited)
        try? await Task.sleep(nanoseconds: 30_000_000)
        expect(service.codex.windows.isEmpty && !service.isRefreshing, "cancelled generation cannot publish late result")
        service.configure(enabled: true, refreshMinutes: 5)
        expect((service.nextRefreshAt?.timeIntervalSinceNow ?? 0) > 890, "late 429 retains fifteen-minute cooldown across stop")
        let counts = await reads.counts
        expect(counts[.codex] == 1 && counts[.claude] == 1, "reenable after late 429 cannot start another process")
        service.stop()
    }
}

private actor FixtureReads {
    private(set) var counts: [AIUsageProvider: Int] = [:]
    func read(_ provider: AIUsageProvider) async -> AIUsageReadResult {
        counts[provider, default: 0] += 1
        try? await Task.sleep(nanoseconds: 10_000_000)
        return AIUsageReadResult(identity: provider.rawValue, snapshot: AIUsageSnapshot(windows: [
            AIUsageWindow(id: "fixture", title: "5 小时", usedPercent: 40, resetAt: Date().addingTimeInterval(600))
        ], updatedAt: Date(), message: nil), failure: nil)
    }
}

private actor DelayedFixtureReads {
    private(set) var counts: [AIUsageProvider: Int] = [:]
    private var continuations: [AIUsageProvider: CheckedContinuation<AIUsageReadResult, Never>] = [:]
    func read(_ provider: AIUsageProvider) async -> AIUsageReadResult {
        counts[provider, default: 0] += 1
        return await withCheckedContinuation { continuations[provider] = $0 }
    }
    func finish(failure: AIUsageFailure) {
        for (provider, continuation) in continuations {
            continuation.resume(returning: AIUsageReadResult(identity: provider.rawValue, snapshot: nil, failure: failure))
        }
        continuations.removeAll()
    }
}

private actor ClaudeFixture {
    private let firstFailure: AIUsageFailure
    private(set) var attempts = 0
    private var reads = 0
    private let old = ClaudeUsageClient.Credential(accessToken: "fixture-old", plan: "max", expiresAt: nil)
    private let current = ClaudeUsageClient.Credential(accessToken: "fixture-new", plan: "max", expiresAt: nil)
    var currentIdentity: String { current.identity }
    init(failure: AIUsageFailure) { firstFailure = failure }
    func credential() -> ClaudeUsageClient.Credential {
        reads += 1
        return reads == 1 ? old : current
    }
    func request(_ credential: ClaudeUsageClient.Credential) -> AIUsageReadResult {
        attempts += 1
        if attempts == 1 { return AIUsageReadResult(identity: credential.identity, snapshot: nil, failure: firstFailure) }
        return AIUsageReadResult(identity: credential.identity, snapshot: AIUsageSnapshot(windows: [
            AIUsageWindow(id: "five", title: "5 小时", usedPercent: 0.5, resetAt: Date().addingTimeInterval(600))
        ], updatedAt: Date(), message: nil), failure: nil)
    }
}
