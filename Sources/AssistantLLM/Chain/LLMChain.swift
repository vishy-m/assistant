import Foundation

public enum ChainError: Error {
    case allProvidersFailed([Error])
    case noProviders
}

public final class LLMChain {

    private let providers: [LLMProvider]

    public init(providers: [LLMProvider]) {
        self.providers = providers
    }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        guard !providers.isEmpty else { throw ChainError.noProviders }

        var errors: [Error] = []
        for provider in providers {
            if !provider.isConfigured() {
                continue
            }
            do {
                return try await provider.complete(messages: messages, tools: tools)
            } catch {
                errors.append(error)
                if !ChainPolicy.shouldFallThrough(error) {
                    throw ChainError.allProvidersFailed(errors)
                }
                continue
            }
        }
        throw ChainError.allProvidersFailed(errors)
    }
}
