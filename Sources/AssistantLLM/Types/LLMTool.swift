import Foundation

public struct LLMTool: Codable, Equatable {
    public let name: String
    public let description: String
    /// JSON Schema (subset) describing arguments.
    public let inputSchema: String

    public init(name: String, description: String, inputSchema: String) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ToolCall: Codable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}
