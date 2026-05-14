import Foundation

public enum ToolRegistryError: Error {
    case unknownTool(String)
    case handlerFailed(String, underlying: Error)
}

public struct ToolRegistry: Sendable {

    public typealias Handler = @Sendable (_ argumentsJSON: String) async throws -> String

    private var tools: [LLMTool] = []
    private var handlers: [String: Handler] = [:]

    public init() {}

    public mutating func register(tool: LLMTool, handler: @escaping Handler) {
        tools.append(tool)
        handlers[tool.name] = handler
    }

    public var toolDefinitions: [LLMTool] { tools }

    public func invoke(name: String, argumentsJSON: String) async throws -> String {
        guard let handler = handlers[name] else { throw ToolRegistryError.unknownTool(name) }
        do {
            return try await handler(argumentsJSON)
        } catch {
            throw ToolRegistryError.handlerFailed(name, underlying: error)
        }
    }
}
