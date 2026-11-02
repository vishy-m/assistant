import Foundation

public enum ToolLoopError: Error {
    /// Retained so existing callers still compile. `run` returns a summary
    /// response instead of throwing this.
    case iterationCapExceeded
    case toolFailed(String, underlying: Error)
}

public final class ToolLoop {

    private let chain: LLMChain
    private let registry: ToolRegistry
    private let maxIterations: Int
    private let maxToolCallsPerResponse: Int
    private let maxToolCallsPerRun: Int

    public init(chain: LLMChain,
                registry: ToolRegistry,
                maxIterations: Int = 8,
                maxToolCallsPerResponse: Int = 8,
                maxToolCallsPerRun: Int = 16) {
        self.chain = chain
        self.registry = registry
        self.maxIterations = maxIterations
        self.maxToolCallsPerResponse = maxToolCallsPerResponse
        self.maxToolCallsPerRun = maxToolCallsPerRun
    }

    public func run(initialMessages: [LLMMessage]) async throws -> LLMResponse {
        var messages = initialMessages
        var completed: [String] = []
        var invocations = 0
        var lastModel = ""

        for _ in 0..<maxIterations {
            let response = try await chain.complete(messages: messages,
                                                    tools: registry.toolDefinitions)
            lastModel = response.modelUsed
            if response.stopReason != .toolUse {
                return response
            }

            let calls = response.toolCalls
            if calls.count > maxToolCallsPerResponse {
                return summary(
                    modelUsed: response.modelUsed,
                    reason: "batch was refused (\(calls.count) calls exceeds per-response cap of \(maxToolCallsPerResponse))",
                    completed: completed)
            }
            let remaining = maxToolCallsPerRun - invocations
            if calls.count > remaining {
                return summary(
                    modelUsed: response.modelUsed,
                    reason: "batch was refused (\(calls.count) calls exceeds remaining run budget of \(remaining); max \(maxToolCallsPerRun) per run)",
                    completed: completed)
            }

            // Append assistant message with the tool_use blocks
            let toolUseBlocks: [LLMContentBlock] = response.content.compactMap { block in
                if case .toolUse = block { return block }
                if case .text = block { return block }
                return nil
            }
            messages.append(LLMMessage(role: .assistant, content: toolUseBlocks))

            // Execute every tool call, append a user message with tool_result blocks.
            // A throw still consumes one invocation; the model sees the error string.
            var resultBlocks: [LLMContentBlock] = []
            for tc in calls {
                let result: String
                do {
                    result = try await registry.invoke(name: tc.name,
                                                       argumentsJSON: tc.argumentsJSON)
                } catch {
                    result = #"{"error":"\#(error)"}"#
                }
                invocations += 1
                completed.append("\(tc.name) id=\(tc.id) result=\(Self.clip(result))")
                resultBlocks.append(.toolResult(toolCallId: tc.id, content: result))
            }
            messages.append(LLMMessage(role: .user, content: resultBlocks))
        }

        return summary(modelUsed: lastModel,
                       reason: "iteration cap of \(maxIterations) reached",
                       completed: completed)
    }

    private func summary(modelUsed: String, reason: String, completed: [String]) -> LLMResponse {
        var lines = ["Tool loop stopped: \(reason)."]
        if completed.isEmpty {
            lines.append("Completed calls: none")
        } else {
            lines.append("Completed calls:")
            lines.append(contentsOf: completed)
        }
        return LLMResponse(modelUsed: modelUsed,
                           stopReason: .endTurn,
                           content: [.text(lines.joined(separator: "\n"))])
    }

    private static func clip(_ text: String) -> String {
        let limit = 300
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "…"
    }
}
