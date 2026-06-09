import XCTest
@testable import AssistantLLM

final class ToolLoopTests: XCTestCase {

    private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
        let name = "scripted"
        private var responses: [LLMResponse]
        init(_ responses: [LLMResponse]) { self.responses = responses }
        func isConfigured() -> Bool { true }
        func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
            precondition(!responses.isEmpty, "exhausted")
            return responses.removeFirst()
        }
    }

    func testToolCallThenTextResolves() async throws {
        // Round 1: model asks to call create_task.
        // Round 2: model says "Done."
        let call = LLMResponse(modelUsed: "x", stopReason: .toolUse,
                               content: [.toolUse(ToolCall(id: "c1", name: "create_task",
                                                            argumentsJSON: #"{"title":"X"}"#))])
        let done = LLMResponse(modelUsed: "x", stopReason: .endTurn,
                               content: [.text("Done.")])
        let chain = LLMChain(providers: [ScriptedProvider([call, done])])

        var registry = ToolRegistry()
        var captured: String?
        registry.register(
            tool: LLMTool(name: "create_task", description: "x",
                          inputSchema: #"{"type":"object"}"#),
            handler: { args in captured = args; return #"{"id":"t1"}"# })

        let loop = ToolLoop(chain: chain, registry: registry, maxIterations: 5)
        let result = try await loop.run(initialMessages: [
            LLMMessage(role: .user, content: [.text("add a task")])
        ])
        XCTAssertEqual(captured, #"{"title":"X"}"#)
        XCTAssertEqual(result.text, "Done.")
    }

    func testIterationCapHit() async {
        // Always responds with another tool call — would loop forever without cap.
        let infinite = LLMResponse(modelUsed: "x", stopReason: .toolUse,
                                   content: [.toolUse(ToolCall(id: "c", name: "echo",
                                                                argumentsJSON: "{}"))])
        let chain = LLMChain(providers: [ScriptedProvider(Array(repeating: infinite, count: 100))])
        var registry = ToolRegistry()
        registry.register(
            tool: LLMTool(name: "echo", description: "x", inputSchema: #"{"type":"object"}"#),
            handler: { _ in "{}" })
        let loop = ToolLoop(chain: chain, registry: registry, maxIterations: 3)
        do {
            _ = try await loop.run(initialMessages: [LLMMessage(role: .user, content: [.text("x")])])
            XCTFail()
        } catch ToolLoopError.iterationCapExceeded {} catch { XCTFail("\(error)") }
    }
}
