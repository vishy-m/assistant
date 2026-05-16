import Foundation
import Security

public enum KeychainAccount: String {
    case claudeAPIKey = "claude_api_key"
    case openaiAPIKey = "openai_api_key"
    case gemmaHostedAPIKey = "gemma_hosted_api_key"
    case googleOAuthRefreshToken = "google_oauth_refresh_token"
    case googleOAuthClientSecret = "google_oauth_client_secret"
}

public struct KeychainStore {
    public static let defaultService = "com.vishruth.assistant"

    private let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    public func set(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidValue
        }
        // Delete any existing item first; SecItemUpdate is awkward with kSecAttrAccessible.
        try? delete(account: account)

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // ThisDeviceOnly: never escrowed to iCloud Keychain or migrated in
            // an encrypted backup. The headless daemon still gets access once
            // the device has been unlocked since boot.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
    }

    public func set(_ account: KeychainAccount, value: String) throws {
        try set(account: account.rawValue, value: value)
    }

    public func get(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
                return nil
            }
            return s
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    public func get(_ account: KeychainAccount) throws -> String? {
        try get(account: account.rawValue)
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Test-only utility — wipes everything under this service.
    public func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }
}

public enum KeychainError: Error {
    case invalidValue
    case osStatus(OSStatus)
}
