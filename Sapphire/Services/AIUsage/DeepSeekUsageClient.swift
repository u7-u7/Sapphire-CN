import Foundation
import CryptoKit

/// 只支持已配置的 DeepSeek 官方 Anthropic 入口；余额查询不会创建模型请求。
enum DeepSeekUsageClient {
    struct Credential: Sendable {
        let accessToken: String
        let configuredEndpoint: String
        var identity: String {
            SHA256.hash(data: Data("deepseek|\(configuredEndpoint)|\(accessToken)".utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
    }

    static func isConfigured(environment: [String: String]) -> Bool {
        guard let base = environment["ANTHROPIC_BASE_URL"], let url = URLComponents(string: base) else { return false }
        return url.scheme == "https" && url.host?.lowercased() == "api.deepseek.com" && url.port == nil
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
            && url.path == "/anthropic"
    }

    static func credential(environment: [String: String]) -> Credential? {
        guard isConfigured(environment: environment) else { return nil }
        let token = ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"].compactMap { environment[$0] }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let token else { return nil }
        return Credential(accessToken: token, configuredEndpoint: "https://api.deepseek.com/anthropic")
    }

    static func fetch(readCredential: () -> Credential?,
                      request: (Credential) async -> AIUsageReadResult = request) async -> AIUsageReadResult {
        guard let credential = readCredential() else {
            return AIUsageReadResult(identity: nil, snapshot: nil, failure: .deepSeekAuthentication, sourceName: "DeepSeek")
        }
        var result = await request(credential)
        result.sourceName = "DeepSeek"
        // 密钥或 endpoint 切换期间的旧余额必须丢弃；不重试另一账号、不绕过共享刷新门禁。
        let current = readCredential()
        if case .rateLimited? = result.failure {
            return AIUsageReadResult(identity: current?.identity, snapshot: nil, failure: .rateLimited, sourceName: "DeepSeek")
        }
        guard current?.identity == credential.identity else {
            return AIUsageReadResult(identity: nil, snapshot: nil, failure: .accountChanged, sourceName: "DeepSeek")
        }
        return result
    }

    private static func request(_ credential: Credential) async -> AIUsageReadResult {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: AIUsageNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIUsageFailure.transport }
            if http.statusCode == 429 { throw AIUsageFailure.rateLimited }
            if [401, 403].contains(http.statusCode) { throw AIUsageFailure.deepSeekAuthentication }
            guard http.statusCode == 200 else { throw AIUsageFailure.transport }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = AIUsageParser.deepSeek(object, at: Date()) else { throw AIUsageFailure.invalidResponse }
            return AIUsageReadResult(identity: credential.identity, snapshot: snapshot, failure: nil, sourceName: "DeepSeek")
        } catch let failure as AIUsageFailure {
            return AIUsageReadResult(identity: credential.identity, snapshot: nil, failure: failure, sourceName: "DeepSeek")
        } catch {
            return AIUsageReadResult(identity: credential.identity, snapshot: nil,
                failure: (error as? URLError)?.code == .timedOut ? .timeout : .transport, sourceName: "DeepSeek")
        }
    }
}
