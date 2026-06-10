import XCTest
@testable import AssistantLLM

final class ToolRegistryTests: XCTestCase {

    func testDispatchKnownTool() async throws {
        var registry = ToolRegistry()
        registry.register(
            tool: LLMTool(name: "echo", description: "echo", inputSchema: #"{"type":"object"}"#),
            handler: { args in args })
        let result = try await registry.invoke(name: "echo", argumentsJSON: #"{"a":1}"#)
        XCTAssertEqual(result, #"{"a":1}"#)
    }

    func testUnknownToolThrows() async {
        let registry = ToolRegistry()
        do {
            _ = try await registry.invoke(name: "nope", argumentsJSON: "{}")
            XCTFail()
        } catch ToolRegistryError.unknownTool {} catch { XCTFail("\(error)") }
    }

    func testHandlerErrorBubbles() async {
        var registry = ToolRegistry()
        registry.register(
            tool: LLMTool(name: "boom", description: "x", inputSchema: #"{"type":"object"}"#),
            handler: { _ in throw NSError(domain: "x", code: 1) })
        do {
            _ = try await registry.invoke(name: "boom", argumentsJSON: "{}")
            XCTFail()
        } catch ToolRegistryError.handlerFailed {} catch { XCTFail("\(error)") }
    }
}
