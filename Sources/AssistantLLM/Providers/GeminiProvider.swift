import Foundation

public final class GeminiProvider: LLMProvider {

    // Newest Stable Flash model, supports function calling, and the one the
    // docs use for generateContent examples (checked 2026-11-02):
    // https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash
    // (gemini-3.6-flash is also Stable but marked previous-generation.)
    public static let defaultModel = "gemini-3.8-flash"
    public let name = "gemini"
    private let provider: GoogleGenerativeLanguageProvider

    public init(http: HTTPClient,
                apiKeyProvider: @escaping @Sendable () -> String?,
                model: String = GeminiProvider.defaultModel) {
        provider = GoogleGenerativeLanguageProvider(name: name, http: http,
                                                     apiKeyProvider: apiKeyProvider, model: model,
                                                     signsForeignFunctionCalls: true)
    }

    public func isConfigured() -> Bool { provider.isConfigured() }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        try await provider.complete(messages: messages, tools: tools)
    }
}
