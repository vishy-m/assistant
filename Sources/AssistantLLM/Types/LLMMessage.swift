import Foundation

public enum LLMRole: String, Codable, Equatable {
    case system
    case user
    case assistant
    case tool
}

public struct LLMImage: Codable, Equatable {
    public let mediaType: String   // e.g. "image/png", "image/jpeg"
    public let data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }
}

public enum LLMContentBlock: Codable, Equatable {
    case text(String)
    case image(LLMImage)
    case toolUse(ToolCall)
    case toolResult(toolCallId: String, content: String)

    enum DiscriminatorKeys: String, CodingKey { case type }
    enum Tag: String, Codable {
        case text, image, toolUse = "tool_use", toolResult = "tool_result"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        switch self {
        case .text(let t):
            try c.encode(Tag.text, forKey: .init("type"))
            try c.encode(t, forKey: .init("text"))
        case .image(let img):
            try c.encode(Tag.image, forKey: .init("type"))
            try c.encode(img, forKey: .init("image"))
        case .toolUse(let tc):
            try c.encode(Tag.toolUse, forKey: .init("type"))
            try c.encode(tc, forKey: .init("tool_call"))
        case .toolResult(let id, let content):
            try c.encode(Tag.toolResult, forKey: .init("type"))
            try c.encode(id, forKey: .init("tool_call_id"))
            try c.encode(content, forKey: .init("content"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let tag = try c.decode(Tag.self, forKey: .init("type"))
        switch tag {
        case .text:
            self = .text(try c.decode(String.self, forKey: .init("text")))
        case .image:
            self = .image(try c.decode(LLMImage.self, forKey: .init("image")))
        case .toolUse:
            self = .toolUse(try c.decode(ToolCall.self, forKey: .init("tool_call")))
        case .toolResult:
            let id = try c.decode(String.self, forKey: .init("tool_call_id"))
            let content = try c.decode(String.self, forKey: .init("content"))
            self = .toolResult(toolCallId: id, content: content)
        }
    }
}

public struct LLMMessage: Codable, Equatable {
    public let role: LLMRole
    public let content: [LLMContentBlock]

    public init(role: LLMRole, content: [LLMContentBlock]) {
        self.role = role
        self.content = content
    }
}

// Helper for dynamic JSON keys.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
