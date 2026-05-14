import Foundation
import AssistantLLM

public struct GCalAuthStore {
    public static let refreshTokenAccount = "google_oauth_refresh_token"

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func setRefreshToken(_ token: String) throws {
        try keychain.set(account: Self.refreshTokenAccount, value: token)
    }

    public func refreshToken() throws -> String? {
        try keychain.get(account: Self.refreshTokenAccount)
    }

    public func clear() throws {
        try keychain.delete(account: Self.refreshTokenAccount)
    }
}
