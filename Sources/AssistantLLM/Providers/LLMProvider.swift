import Foundation

public protocol LLMProvider: Sendable {
    /// Identifier for logging and budget tracking ("claude", "openai", etc.)
    var name: String { get }

    /// Does this provider currently have configuration to run? (e.g., API key in Keychain.)
    func isConfigured() -> Bool

    /// Sends the conversation + tool list to the provider and returns one model response.
    /// Throws ProviderError on failure; the chain inspects the error to decide on fallthrough.
    func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse
}

public enum ProviderError: Error, Equatable {
    case notConfigured
    case rateLimited            // HTTP 429
    case serverOverloaded       // HTTP 529 (Anthropic)
    case transient(message: String)   // 5xx, network drop
    case timeout
    case clientError(statusCode: Int, message: String)   // 4xx (non-429)
    case decodingFailure(message: String)
}
