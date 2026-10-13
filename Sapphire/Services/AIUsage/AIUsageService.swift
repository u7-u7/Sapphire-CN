import Foundation
import Combine

struct AIUsageRuntimeConfiguration: Equatable {
    let enabled: Bool
    let refreshMinutes: Int
    let codex: ThirdPartyUsageConfiguration
    let claude: ThirdPartyUsageConfiguration
}

@MainActor
final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()
    @Published private(set) var codex = AIUsageSnapshot()
    @Published private(set) var claude = AIUsageSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var nextRefreshAt: Date?

    private var enabled = false
    private var refreshMinutes = 5
    private var generation = 0
    private var configurations: [AIUsageProvider: ThirdPartyUsageConfiguration] = [:]
    private var gates: [AIUsageProvider: AIUsageRequestGate] = [:]
    private var identities: [AIUsageProvider: String] = [:]
    private var testingProviders: Set<AIUsageProvider> = []
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var keyChanges: AnyCancellable?
    private let fetchCodex: () async -> AIUsageReadResult
    private let fetchClaude: () async -> AIUsageReadResult
    private let readCredential: (AIUsageProvider, ThirdPartyUsageConfiguration, String?) async -> ThirdPartyUsageClient.Credential?
    private let thirdPartySender: ThirdPartyUsageClient.Sender?

    /// 默认构造不读凭据或联网，注入用于离线验证。
    init(fetchCodex: @escaping () async -> AIUsageReadResult = { await AIUsageService.defaultFetch(.codex) },
         fetchClaude: @escaping () async -> AIUsageReadResult = { await AIUsageService.defaultFetch(.claude) },
         readCredential: @escaping (AIUsageProvider, ThirdPartyUsageConfiguration, String?) async -> ThirdPartyUsageClient.Credential? = {
             await AIUsageCLIResolver.credential(for: $0, configuration: $1, queryKey: $2)
         }, thirdPartySender: ThirdPartyUsageClient.Sender? = nil) {
        self.fetchCodex = fetchCodex
        self.fetchClaude = fetchClaude
        self.readCredential = readCredential
        self.thirdPartySender = thirdPartySender
        keyChanges = NotificationCenter.default.publisher(for: .aiUsageQueryKeyChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let name = notification.object as? String, let provider = AIUsageProvider(rawValue: name) else { return }
                self?.queryKeyChanged(provider)
            }
    }

    func configure(enabled: Bool, refreshMinutes: Int,
                   codex: ThirdPartyUsageConfiguration = .init(), claude: ThirdPartyUsageConfiguration = .init()) {
        let changed = AIUsageProvider.allCases.filter { configurations[$0, default: .init()] != ($0 == .codex ? codex : claude) }
        configurations = [.codex: codex, .claude: claude]
        if !changed.isEmpty {
            cancelRefresh()
            changed.forEach { clearReading($0) }
        }
        guard enabled else { if self.enabled { stop() }; return }
        let minutes = [5, 15, 30].contains(refreshMinutes) ? refreshMinutes : 5
        let wasEnabled = self.enabled
        let intervalChanged = self.refreshMinutes != minutes
        self.enabled = true
        self.refreshMinutes = minutes
        if !wasEnabled || !changed.isEmpty { refresh() }
        else if intervalChanged { scheduleNextRefresh() }
        startPollingIfNeeded()
    }

    func refresh() {
        guard enabled, !isRefreshing else { return }
        expireReadings()
        let now = Date()
        let readCodex = claim(.codex, at: now)
        let readClaude = claim(.claude, at: now)
        guard readCodex || readClaude else { if nextRefreshAt == nil { scheduleNextRefresh() }; return }
        isRefreshing = true
        let currentGeneration = generation
        let captured = configurations
        refreshTask = Task { [weak self] in
            guard let self else { return }
            async let codexResult: AIUsageReadResult? = readCodex ? self.fetch(.codex, configuration: captured[.codex, default: .init()]) : nil
            async let claudeResult: AIUsageReadResult? = readClaude ? self.fetch(.claude, configuration: captured[.claude, default: .init()]) : nil
            let results = await (codexResult, claudeResult)
            // 已发请求的晚到 429 始终进入门禁，关闭开关或改地址不能跳过冷却。
            self.recordFailure(results.0?.failure, for: .codex)
            self.recordFailure(results.1?.failure, for: .claude)
            guard !Task.isCancelled, self.enabled, self.generation == currentGeneration else { return }
            if let result = results.0 { self.apply(result, for: .codex) }
            if let result = results.1 { self.apply(result, for: .claude) }
            self.isRefreshing = false
            self.refreshTask = nil
            self.scheduleNextRefresh()
        }
    }

    /// 草稿测试仅返回预览，既不写配置、存密钥，也不覆盖正常组件读数。
    func test(provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration, queryKey: String? = nil) async -> AIUsageSnapshot {
        guard !isRefreshing, !testingProviders.contains(provider) else {
            return AIUsageSnapshot(message: "已有查询正在进行，请稍后测试", sourceName: configuration.displayName)
        }
        if let failure = validationFailure(configuration) {
            return AIUsageSnapshot(message: failure.message, sourceName: configuration.displayName)
        }
        testingProviders.insert(provider)
        defer { testingProviders.remove(provider); if enabled { scheduleNextRefresh() } }
        guard let credential = await readCredential(provider, configuration, queryKey), !Task.isCancelled else {
            return AIUsageSnapshot(message: AIUsageFailure.thirdPartyAuthentication(provider).message, sourceName: configuration.displayName)
        }
        guard ThirdPartyUsageClient.sameEndpoint(credential.configuredEndpoint, configuration.providerBaseURL) else {
            return AIUsageSnapshot(message: AIUsageFailure.thirdPartyEndpointChanged.message, sourceName: configuration.displayName)
        }
        var gate = gates[provider, default: .init()]
        let now = Date()
        guard gate.claim(at: now) else {
            let wait = Int(ceil(gate.allowedAt(now: now).timeIntervalSince(now) / 60))
            return AIUsageSnapshot(message: "请求间隔或限流冷却尚未结束，请在约 \(wait) 分钟后测试", sourceName: configuration.displayName)
        }
        gates[provider] = gate
        let result = await fetchThirdParty(provider, configuration: configuration, queryKey: queryKey)
        recordFailure(result.failure, for: provider)
        return result.snapshot?.expiringWindows(at: Date())
            ?? AIUsageSnapshot(message: result.failure?.message ?? AIUsageFailure.invalidResponse.message, sourceName: result.sourceName)
    }

    func stop() {
        enabled = false
        cancelRefresh()
        pollingTask?.cancel()
        pollingTask = nil
        nextRefreshAt = nil
        // 保留门禁，禁用后重启仍遵循原请求间隔与冷却。
    }

    private func fetch(_ provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration) async -> AIUsageReadResult {
        if configuration.enabled {
            if let failure = validationFailure(configuration) {
                return AIUsageReadResult(identity: nil, snapshot: nil, failure: failure, sourceName: configuration.displayName)
            }
            return await fetchThirdParty(provider, configuration: configuration)
        }
        return await (provider == .codex ? fetchCodex() : fetchClaude())
    }

    private func fetchThirdParty(_ provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration,
                                queryKey: String? = nil) async -> AIUsageReadResult {
        let reader = readCredential
        let read = { await reader(provider, configuration, queryKey) }
        if let sender = thirdPartySender {
            return await ThirdPartyUsageClient.fetch(provider: provider, configuration: configuration, readCredential: read, send: sender)
        }
        return await ThirdPartyUsageClient.fetch(provider: provider, configuration: configuration, readCredential: read)
    }

    private func validationFailure(_ configuration: ThirdPartyUsageConfiguration) -> AIUsageFailure? {
        guard let base = URLComponents(string: configuration.providerBaseURL), base.scheme?.lowercased() == "https",
              base.host != nil, base.user == nil, base.password == nil else {
            return .thirdPartyConfiguration("请填写当前供应商的完整 HTTPS 模型地址")
        }
        do {
            _ = try ThirdPartyUsageClient.makeRequest(configuration: configuration,
                credential: .init(accessToken: "validation", configuredEndpoint: configuration.providerBaseURL))
            if configuration.template == .custom && [configuration.remainingPath, configuration.usedPath, configuration.totalPath].allSatisfy({ $0.isEmpty }) {
                return .thirdPartyConfiguration("请至少填写一个额度数值字段")
            }
            return nil
        } catch let failure as AIUsageFailure { return failure }
        catch { return .invalidResponse }
    }

    private static func defaultFetch(_ provider: AIUsageProvider) async -> AIUsageReadResult {
        let binding = await Task.detached(priority: .utility) { AIUsageCLIResolver.read(provider: provider) }.value
        if let binding, binding.isThirdParty {
            if provider == .claude && DeepSeekUsageClient.isConfigured(environment: ["ANTHROPIC_BASE_URL": binding.endpoint]) {
                return await ClaudeUsageClient.fetch()
            }
            return AIUsageReadResult(identity: nil, snapshot: nil,
                failure: .thirdPartyConfiguration("当前使用 API Key，请配置该供应商的额度查询地址"), sourceName: "第三方平台")
        }
        guard binding != nil else {
            return AIUsageReadResult(identity: nil, snapshot: nil,
                failure: .thirdPartyConfiguration("无法确认 CLI 供应商配置，请检查命名 provider 或 profile"), sourceName: "CLI 配置")
        }
        return await (provider == .codex ? CodexUsageClient.fetch() : ClaudeUsageClient.fetch())
    }

    private func queryKeyChanged(_ provider: AIUsageProvider) {
        guard configurations[provider]?.enabled == true, configurations[provider]?.credentialSource == .separateQueryKey else { return }
        cancelRefresh()
        clearReading(provider)
        if enabled { refresh() }
    }

    private func clearReading(_ provider: AIUsageProvider) {
        identities.removeValue(forKey: provider)
        let config = configurations[provider, default: .init()]
        let empty = AIUsageSnapshot(message: "配置已变化，等待下一次查询", sourceName: config.enabled ? config.displayName : nil)
        if provider == .codex { codex = empty } else { claude = empty }
    }

    private func cancelRefresh() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private func claim(_ provider: AIUsageProvider, at now: Date) -> Bool {
        guard !testingProviders.contains(provider) else { return false }
        var gate = gates[provider, default: .init()]
        let allowed = gate.claim(at: now)
        gates[provider] = gate
        return allowed
    }

    private func apply(_ result: AIUsageReadResult, for provider: AIUsageProvider) {
        let now = Date()
        let prior = provider == .codex ? codex : claude
        let sameIdentity = result.identity != nil && result.identity == identities[provider]
        var snapshot: AIUsageSnapshot
        if let fresh = result.snapshot { snapshot = fresh.expiringWindows(at: now) }
        else {
            snapshot = AIUsageSnapshot.retaining(prior, for: result.failure ?? .invalidResponse, sameIdentity: sameIdentity, at: now)
            snapshot.sourceName = result.sourceName
        }
        identities[provider] = result.identity
        if provider == .codex { codex = snapshot } else { claude = snapshot }
    }

    private func recordFailure(_ failure: AIUsageFailure?, for provider: AIUsageProvider) {
        gates[provider]?.record(failure, at: Date())
    }

    private func scheduleNextRefresh() {
        guard enabled else { nextRefreshAt = nil; return }
        let now = Date()
        let planned = now.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        nextRefreshAt = AIUsageProvider.allCases.map { max(planned, gates[$0, default: .init()].allowedAt(now: now)) }.min()
    }

    private func expireReadings() {
        codex = codex.expiringWindows(at: Date())
        claude = claude.expiringWindows(at: Date())
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self, self.enabled else { return }
                self.expireReadings()
                if let next = self.nextRefreshAt, next <= Date(), !self.isRefreshing { self.refresh() }
            }
        }
    }
}
