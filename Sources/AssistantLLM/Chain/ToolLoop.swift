import Foundation

public enum ToolLoopError: Error {
    case iterationCapExceeded
    case toolFailed(String, underlying: Error)
}

public final class ToolLoop {

    private let chain: LLMChain
    private let registry: ToolRegistry
    private let maxIterations: Int

    public init(chain: LLMChain, registry: ToolRegistry, maxIterations: Int = 8) {
        self.chain = chain
        self.registry = registry
        self.maxIterations = maxIterations
    }

    public func run(initialMessages: [LLMMessage]) async throws -> LLMResponse {
        var messages = initialMessages

        for _ in 0..<maxIterations {
            let response = try await chain.complete(messages: messages,
                                                    tools: registry.toolDefinitions)
            if response.stopReason != .toolUse {
                return response
            }

            // Append assistant message with the tool_use blocks
            let toolUseBlocks: [LLMContentBlock] = response.content.compactMap { block in
                if case .toolUse = block { return block }
                if case .text = block { return block }
                return nil
            }
            messages.append(LLMMessage(role: .assistant, content: toolUseBlocks))

            // Execute every tool call, append a user message with tool_result blocks
            var resultBlocks: [LLMContentBlock] = []
            for tc in response.toolCalls {
                do {
                    let result = try await registry.invoke(name: tc.name,
                                                           argumentsJSON: tc.argumentsJSON)
                    resultBlocks.append(.toolResult(toolCallId: tc.id, content: result))
                } catch {
                    // Surface the error back to the model so it can react.
                    let errMsg = #"{"error":"\#(error)"}"#
                    resultBlocks.append(.toolResult(toolCallId: tc.id, content: errMsg))
                }
            }
            messages.append(LLMMessage(role: .user, content: resultBlocks))
        }

        throw ToolLoopError.iterationCapExceeded
    }
}
