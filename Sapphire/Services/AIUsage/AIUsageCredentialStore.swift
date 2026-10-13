import Foundation
import Security
import LocalAuthentication
import CryptoKit

extension Notification.Name {
    static let aiUsageQueryKeyChanged = Notification.Name("aiUsageQueryKeyChanged")
}

/// 查询专用密钥沿用应用的 KeychainStore，不进入 Settings 或导出的备份。
enum AIUsageCredentialStore {
    private static let service = "com.cshariq.sapphire.ai-usage"
    static func credentialScope(for provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration) -> String {
        // 密钥绑定查询目标和认证上下文；修改查询地址不能把旧密钥发送到新的目标。
        let fields = [provider.rawValue, configuration.providerBaseURL, configuration.queryURL,
            configuration.authentication.rawValue, configuration.userID]
        let context = (try? JSONEncoder().encode(fields)) ?? Data()
        return provider.rawValue + "." + SHA256.hash(data: context)
            .map { String(format: "%02x", $0) }.joined()
    }

    static func queryKey(for provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration) -> String? {
        let query = readQuery(provider, configuration, returnData: true)
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasQueryKey(for provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration) -> Bool {
        var value: CFTypeRef?
        return SecItemCopyMatching(readQuery(provider, configuration, returnData: false) as CFDictionary, &value) == errSecSuccess
    }

    static func setQueryKey(_ value: String, for provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { try removeQueryKey(for: provider, configuration: configuration); return }
        let status = KeychainStore.setItem(service: service, account: credentialScope(for: provider, configuration: configuration),
            data: Data(trimmed.utf8), accessible: kSecAttrAccessibleAfterFirstUnlock, synchronizable: false)
        guard status == errSecSuccess else { throw StoreError.writeFailed }
        NotificationCenter.default.post(name: .aiUsageQueryKeyChanged, object: provider.rawValue)
    }

    static func removeQueryKey(for provider: AIUsageProvider, configuration: ThirdPartyUsageConfiguration) throws {
        let status = KeychainStore.deleteItem(service: service, account: credentialScope(for: provider, configuration: configuration), synchronizable: false)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.writeFailed }
        NotificationCenter.default.post(name: .aiUsageQueryKeyChanged, object: provider.rawValue)
    }

    private static func readQuery(_ provider: AIUsageProvider, _ configuration: ThirdPartyUsageConfiguration, returnData: Bool) -> [String: Any] {
        // 后台刷新不弹出 Keychain 解锁或跨签名访问对话框；不可读时由设置页提示重新保存。
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: credentialScope(for: provider, configuration: configuration), kSecMatchLimit as String: kSecMatchLimitOne,
            (returnData ? kSecReturnData : kSecReturnAttributes) as String: true,
            kSecAttrSynchronizable as String: false, kSecUseAuthenticationContext as String: context]
    }

    enum StoreError: LocalizedError {
        case writeFailed
        var errorDescription: String? { NSLocalizedString("Unable to save the query key in Keychain.", comment: "Quota key storage error") }
    }
}
