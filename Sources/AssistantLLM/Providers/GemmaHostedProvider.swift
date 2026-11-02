import Foundation

public final class GemmaHostedProvider: LLMProvider {

    public let name = "gemma_hosted"
    private let provider: GoogleGenerativeLanguageProvider

    public init(http: HTTPClient,
                apiKeyProvider: @escaping @Sendable () -> String?,
                model: String = "gemma-4-31b-it") {
        provider = GoogleGenerativeLanguageProvider(name: name, http: http,
                                                     apiKeyProvider: apiKeyProvider, model: model)
    }

    public func isConfigured() -> Bool { provider.isConfigured() }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        try await provider.complete(messages: messages, tools: tools)
    }
}
