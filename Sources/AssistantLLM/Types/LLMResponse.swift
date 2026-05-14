import Foundation

public enum LLMStopReason: String, Codable {
    case endTurn = "end_turn"
    case toolUse = "tool_use"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
}

public struct LLMResponse: Codable, Equatable {
    public let modelUsed: String
    public let stopReason: LLMStopReason
    public let content: [LLMContentBlock]   // may contain text and/or toolUse blocks

    public init(modelUsed: String, stopReason: LLMStopReason, content: [LLMContentBlock]) {
        self.modelUsed = modelUsed
        self.stopReason = stopReason
        self.content = content
    }

    /// Convenience: joined text of all text blocks (empty if there's only tool use).
    public var text: String {
        content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
               .joined(separator: "\n")
    }

    public var toolCalls: [ToolCall] {
        content.compactMap { if case .toolUse(let tc) = $0 { return tc } else { return nil } }
    }
}
