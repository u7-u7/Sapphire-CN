import Foundation

// Integration fixtures only: fake CLI text, fake keys, mocked HTTP. Never read or write real credentials.
@main struct VerifyAIUsageIntegration {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message); checks += 1
    }
    static func config() -> ThirdPartyUsageConfiguration {
        var result = ThirdPartyUsageConfiguration()
        result.enabled = true
        result.platformName = "Fixture"
        result.providerBaseURL = "https://provider.invalid/v1"
        result.queryURL = "https://provider.invalid/balance"
        result.remainingPath = "balance"
        result.unit = "CNY"
        return result
    }
    @MainActor static func main() async throws {
        verifyResolvers()
        verifyKeyScope()
        try await verifyTestIsolation()
        await verifyConfigGeneration()
        print("PASS: \(checks) CLI binding, key scope and service integration checks; no real credentials or HTTP")
    }
    static func verifyResolvers() {
        let auth = Data(#"{"OPENAI_API_KEY":"fixture-only"}"#.utf8)
        let named = AIUsageCLIResolver.codex(config: "model_provider='relay'\n[model_providers.relay]\nbase_url='https://relay.invalid/v1'", authData: auth, environment: [:])
        expect(named?.endpoint == "https://relay.invalid/v1" && named?.apiKey == "fixture-only", "named provider uses its own endpoint/key")
        let profile = AIUsageCLIResolver.codex(config: "profile='work'\n[profiles.work]\nmodel_provider='relay'\n[model_providers.relay]\nbase_url='https://relay.invalid/v1'\nenv_key='QUOTA_FIXTURE_KEY'", authData: auth, environment: ["QUOTA_FIXTURE_KEY":"env-fixture"])
        expect(profile?.endpoint == "https://relay.invalid/v1" && profile?.apiKey == "env-fixture", "profile and env_key are respected")
        let absent = AIUsageCLIResolver.codex(config: "profile='missing'", authData: auth, environment: [:])
        expect(absent == nil, "unresolved profile never guesses another provider")
        let instructions = "developer_instructions='''\n[model_providers.openai]\nbase_url=\"https://fake.invalid\"\n'''\nmodel_provider='openai'"
        let parsed = AIUsageCLIResolver.codex(config: instructions, authData: nil, environment: [:])
        expect(parsed?.endpoint == "https://api.openai.com/v1", "multiline instruction text cannot create a provider")
        expect(CodexUsageTOML.strings("developer_instructions=\"\"\"unclosed") == nil, "unfinished multiline strings fail closed")
        let quoted = AIUsageCLIResolver.codex(config: "model_provider='a.b'\n[model_providers.\"a.b\"]\nbase_url='https://quoted.invalid/v1' # comment", authData: auth, environment: [:])
        expect(quoted?.endpoint == "https://quoted.invalid/v1", "quoted provider names and trailing comments parse")
        let claude = AIUsageCLIResolver.claude(environment: ["ANTHROPIC_BASE_URL":"https://shell.invalid","ANTHROPIC_AUTH_TOKEN":"shell-fixture"], settingsData: Data(#"{"env":{"ANTHROPIC_BASE_URL":"https://configured.invalid","ANTHROPIC_AUTH_TOKEN":"configured-fixture"}}"#.utf8))
        expect(claude.endpoint == "https://configured.invalid" && claude.apiKey == "configured-fixture", "Claude settings env takes priority")
    }
    static func verifyKeyScope() {
        let original = config()
        let scope = AIUsageCredentialStore.credentialScope(for: .codex, configuration: original)
        var changed = original; changed.queryURL = "https://another.invalid/balance"
        expect(scope != AIUsageCredentialStore.credentialScope(for: .codex, configuration: changed), "new query destination cannot reuse old key")
        changed = original; changed.providerBaseURL = "https://another-model.invalid/v1"
        expect(scope != AIUsageCredentialStore.credentialScope(for: .codex, configuration: changed), "model binding isolates keys")
        expect(scope != AIUsageCredentialStore.credentialScope(for: .claude, configuration: original), "Codex and Claude keys are isolated")
        changed = original; changed.userID = "other-user"
        expect(scope != AIUsageCredentialStore.credentialScope(for: .codex, configuration: changed), "account context isolates query tokens")
        changed = original; changed.remainingPath = "new.balance"
        expect(scope == AIUsageCredentialStore.credentialScope(for: .codex, configuration: changed), "field mapping edits do not require reentering same-target key")
    }
    @MainActor static func verifyTestIsolation() async throws {
        let calls = IntegrationCalls()
        let service = AIUsageService(fetchCodex: { .init(identity:nil,snapshot:nil,failure:.transport) }, fetchClaude: { .init(identity:nil,snapshot:nil,failure:.transport) }, readCredential: { _, configuration, override in
            .init(accessToken: override ?? "fixture-only", configuredEndpoint: configuration.providerBaseURL)
        }, thirdPartySender: { request in await calls.send(request) })
        var invalid = config(); invalid.queryURL = "http://insecure.invalid"
        let rejected = await service.test(provider: .codex, configuration: invalid)
        expect(rejected.message != nil, "invalid draft is rejected before networking")
        let result = await service.test(provider: .codex, configuration: config(), queryKey: "draft-fixture")
        expect(result.amounts.first?.remaining == Decimal(12), "draft key test returns mapped result")
        expect(service.codex.amounts.isEmpty && service.codex.updatedAt == nil, "testing never publishes normal component state")
        let limited = await service.test(provider: .codex, configuration: config())
        expect(limited.message?.contains("间隔") == true, "tests share minimum request interval")
        expect(await calls.count == 1, "invalid draft and repeated test do not send extra requests")
        service.configure(enabled: true, refreshMinutes: 5, codex: config())
        try? await Task.sleep(nanoseconds: 40_000_000)
        expect(await calls.count == 1, "normal refresh cannot bypass previous test gate")
        service.stop()
    }
    @MainActor static func verifyConfigGeneration() async {
        let pending = PendingIntegrationCall()
        let service = AIUsageService(fetchCodex: { .init(identity:nil,snapshot:nil,failure:.transport) }, fetchClaude: { .init(identity:nil,snapshot:nil,failure:.transport) }, readCredential: { _, configuration, _ in
            .init(accessToken: "fixture-only", configuredEndpoint: configuration.providerBaseURL)
        }, thirdPartySender: { request in await pending.send(request) })
        let original = config()
        service.configure(enabled: true, refreshMinutes: 5, codex: original)
        for _ in 0..<40 {
            if await pending.waiting { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        expect(await pending.waiting, "mock request started")
        var changed = original; changed.platformName = "New fixture"; changed.queryURL = "https://provider.invalid/new-balance"
        service.configure(enabled: true, refreshMinutes: 5, codex: changed)
        await pending.finish()
        try? await Task.sleep(nanoseconds: 30_000_000)
        expect(service.codex.amounts.isEmpty && service.codex.sourceName == "New fixture", "old response cannot fill new configuration")
        service.stop()
    }
}
private actor IntegrationCalls {
    private(set) var count = 0
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        count += 1
        return (Data(#"{"balance":"12.00"}"#.utf8), HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
}
private actor PendingIntegrationCall {
    private var continuation: CheckedContinuation<(Data,HTTPURLResponse),Never>?
    private var url: URL?
    var waiting: Bool { continuation != nil }
    func send(_ request: URLRequest) async -> (Data, HTTPURLResponse) {
        url = request.url
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning:(Data(#"{"balance":"999.00"}"#.utf8),HTTPURLResponse(url:url!,statusCode:200,httpVersion:nil,headerFields:nil)!))
        continuation = nil
    }
}
