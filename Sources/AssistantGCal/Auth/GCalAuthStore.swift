import Foundation
import AssistantLLM

public struct GCalAuthStore {
    private let secrets: SecretStore

    public init(secrets: SecretStore = SecretStore()) {
        self.secrets = secrets
    }

    public func setRefreshToken(_ token: String) throws {
        try secrets.set(.googleOAuthRefreshToken, value: token)
    }

    public func refreshToken() throws -> String? {
        try secrets.get(.googleOAuthRefreshToken)
    }

    public func clear() throws {
        try secrets.delete(.googleOAuthRefreshToken)
    }
}
