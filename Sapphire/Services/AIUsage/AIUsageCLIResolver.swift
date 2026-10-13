import Foundation

/// 只读取 CLI 已保存的配置。env_key 仅查当前应用环境，不运行 api_key_helper 或 shell。
enum AIUsageCLIResolver {
    struct Binding: Sendable {
        let endpoint: String
        let apiKey: String?
        let isThirdParty: Bool
    }

    static func credential(for provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration,
                           queryKey: String? = nil) async -> ThirdPartyUsageClient.Credential? {
        await Task.detached(priority: .utility) {
            guard let binding = read(provider: provider) else { return nil }
            let key: String
            if configuration.authentication == .none { key = "" }
            else if let queryKey, !queryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { key = queryKey }
            else if configuration.credentialSource == .separateQueryKey {
                guard let saved = AIUsageCredentialStore.queryKey(for: provider, configuration: configuration) else { return nil }
                key = saved
            } else {
                guard let current = binding.apiKey, !current.isEmpty else { return nil }
                key = current
            }
            return ThirdPartyUsageClient.Credential(accessToken: key, configuredEndpoint: binding.endpoint)
        }.value
    }

    static func read(provider: AIUsageProvider, environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: String = NSHomeDirectory()) -> Binding? {
        switch provider {
        case .claude:
            let directory = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.claude"
            let settings = FileManager.default.contents(atPath: "\(NSString(string: directory).expandingTildeInPath)/settings.json")
            return claude(environment: environment, settingsData: settings)
        case .codex:
            let directory = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.codex"
            let root = NSString(string: directory).expandingTildeInPath
            let config = (try? String(contentsOfFile: "\(root)/config.toml", encoding: .utf8)) ?? ""
            let auth = FileManager.default.contents(atPath: "\(root)/auth.json")
            return codex(config: config, authData: auth, environment: environment)
        }
    }

    static func claude(environment: [String: String], settingsData: Data?) -> Binding {
        let values = ClaudeUsageClient.effectiveEnvironment(environment: environment, settingsData: settingsData)
        let endpoint = nonEmpty(values["ANTHROPIC_BASE_URL"]) ?? "https://api.anthropic.com"
        let key = nonEmpty(values["ANTHROPIC_AUTH_TOKEN"]) ?? nonEmpty(values["ANTHROPIC_API_KEY"])
        let thirdParty = URLComponents(string: endpoint)?.host?.lowercased() != "api.anthropic.com" || key != nil
        return Binding(endpoint: endpoint, apiKey: key, isThirdParty: thirdParty)
    }

    static func codex(config: String, authData: Data?, environment: [String: String]) -> Binding? {
        // 只支持 CLI 标准顶层 model_provider 和命名 provider 表；无法确认的 TOML 不猜供应商。
        guard let tables = CodexUsageTOML.strings(config) else { return nil }
        let profile = tables[""]?["profile"]
        if let profile, tables["profiles.\(profile)"] == nil { return nil }
        let provider = profile.flatMap { tables["profiles.\($0)"]?["model_provider"] }
            ?? tables[""]?["model_provider"] ?? "openai"
        let values = tables["model_providers.\(provider)"] ?? [:]
        let endpoint: String
        if let configured = nonEmpty(values["base_url"]) { endpoint = configured }
        else if provider == "openai" { endpoint = nonEmpty(environment["OPENAI_BASE_URL"]) ?? "https://api.openai.com/v1" }
        else { return nil }
        let auth = authData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let key: String?
        if let variable = nonEmpty(values["env_key"]) { key = nonEmpty(environment[variable]) }
        else {
            key = nonEmpty(values["experimental_bearer_token"])
                ?? nonEmpty(auth?["OPENAI_API_KEY"] as? String) ?? nonEmpty(environment["OPENAI_API_KEY"])
        }
        let thirdParty = provider != "openai" || key != nil
            || URLComponents(string: endpoint)?.host?.lowercased() != "api.openai.com"
        return Binding(endpoint: endpoint, apiKey: key, isThirdParty: thirdParty)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
}

/// 最小 TOML 字符串读取器，支持标准引号/字面量字符串、注释、引号包裹的 provider 名。
/// 多行目标字符串、重复目标键和未知转义会失败，防止错误选路后把 key 发给其他供应商。
enum CodexUsageTOML {
    static func strings(_ input: String) -> [String: [String: String]]? {
        var table = ""
        var output: [String: [String: String]] = ["": [:]]
        var multiline: String?
        for raw in input.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let delimiter = multiline {
                if closesMultiline(line, delimiter: delimiter) { multiline = nil }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let equal = line.firstIndex(of: "=") {
                let key = line[..<equal].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"\"\"") || value.hasPrefix("'''") {
                    if ["profile", "model_provider", "base_url", "env_key", "experimental_bearer_token"].contains(key) { return nil }
                    let delimiter = String(value.prefix(3))
                    if !closesMultiline(String(value.dropFirst(3)), delimiter: delimiter) { multiline = delimiter }
                    continue
                }
            }
            // 嵌套数组中的多行字符串未受支持；失败而不是把字符串正文解释为配置。
            if line.contains("\"\"\"") || line.contains("'''") { return nil }
            if line.hasPrefix("[") {
                guard !line.hasPrefix("[["), let close = line.firstIndex(of: "]") else { table = "unsupported"; continue }
                let parts = line[line.index(after: line.startIndex)..<close].split(separator: ".")
                table = parts.map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }.joined(separator: ".")
                if output[table] == nil { output[table] = [:] }
                continue
            }
            guard let equal = line.firstIndex(of: "=") else { continue }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard ["profile", "model_provider", "base_url", "env_key", "experimental_bearer_token"].contains(key),
                  table == "" || table.hasPrefix("model_providers.") || table.hasPrefix("profiles.") else { continue }
            let valueText = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            guard let value = quoted(valueText), output[table]?[key] == nil else { return nil }
            output[table, default: [:]][key] = value
        }
        return multiline == nil ? output : nil
    }

    private static func closesMultiline(_ text: String, delimiter: String) -> Bool {
        var search = text.startIndex
        while let range = text.range(of: delimiter, range: search..<text.endIndex) {
            if delimiter == "'''" { return true }
            var slashes = 0
            var before = range.lowerBound
            while before > text.startIndex {
                before = text.index(before: before)
                guard text[before] == "\\" else { break }
                slashes += 1
            }
            if slashes.isMultiple(of: 2) { return true }
            search = range.upperBound
        }
        return false
    }

    private static func quoted(_ text: String) -> String? {
        guard let quote = text.first, quote == "\"" || quote == "'", !text.hasPrefix(String(repeating: String(quote), count: 3)) else { return nil }
        var value = ""
        var escaped = false
        for index in text.indices.dropFirst() {
            let character = text[index]
            if escaped {
                switch character {
                case "\"", "\\": value.append(character)
                case "n": value.append("\n")
                case "r": value.append("\r")
                case "t": value.append("\t")
                default: return nil
                }
                escaped = false
            } else if quote == "\"" && character == "\\" { escaped = true }
            else if character == quote {
                let rest = text[text.index(after: index)...].trimmingCharacters(in: .whitespaces)
                return rest.isEmpty || rest.hasPrefix("#") ? value : nil
            } else { value.append(character) }
        }
        return nil
    }
}
