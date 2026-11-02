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

    func testIterationCapHit() async throws {
        // Always responds with another tool call — would loop forever without cap.
        let infinite = LLMResponse(modelUsed: "x", stopReason: .toolUse,
                                   content: [.toolUse(ToolCall(id: "c", name: "echo",
                                                                argumentsJSON: "{}"))])
        let chain = LLMChain(providers: [ScriptedProvider(Array(repeating: infinite, count: 100))])
        var registry = ToolRegistry()
        var invocations = 0
        registry.register(
            tool: LLMTool(name: "echo", description: "x", inputSchema: #"{"type":"object"}"#),
            handler: { _ in
                invocations += 1
                return "{\"ok\":\(invocations)}"
            })
        let loop = ToolLoop(chain: chain, registry: registry, maxIterations: 3)
        let result = try await loop.run(initialMessages: [LLMMessage(role: .user, content: [.text("x")])])
        XCTAssertEqual(invocations, 3)
        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertTrue(result.text.contains("iteration cap"))
        XCTAssertTrue(result.text.contains("3"))
        XCTAssertTrue(result.text.contains("echo"))
        XCTAssertTrue(result.text.contains("{\"ok\":1}"))
        XCTAssertTrue(result.text.contains("{\"ok\":3}"))
    }

    func testPerResponseCapRefusesTheWholeBatch() async throws {
        let calls: [LLMContentBlock] = (0..<10).map { index in
            .toolUse(ToolCall(id: "c\(index)", name: "create_task", argumentsJSON: "{}"))
        }
        let batch = LLMResponse(modelUsed: "x", stopReason: .toolUse, content: calls)
        let done = LLMResponse(modelUsed: "x", stopReason: .endTurn, content: [.text("should not continue")])
        let chain = LLMChain(providers: [ScriptedProvider([batch, done])])
        var registry = ToolRegistry()
        var invocations = 0
        registry.register(
            tool: LLMTool(name: "create_task", description: "x", inputSchema: #"{"type":"object"}"#),
            handler: { _ in
                invocations += 1
                return "{}"
            })
        let loop = ToolLoop(chain: chain, registry: registry,
                            maxIterations: 8,
                            maxToolCallsPerResponse: 8,
                            maxToolCallsPerRun: 16)
        let result = try await loop.run(initialMessages: [LLMMessage(role: .user, content: [.text("x")])])
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertTrue(result.text.contains("refused"))
    }

    func testRunBudgetRefusesTheNextWholeBatch() async throws {
        func batch(_ prefix: String) -> LLMResponse {
            let calls: [LLMContentBlock] = (0..<6).map { index in
                .toolUse(ToolCall(id: "\(prefix)\(index)", name: "create_task", argumentsJSON: "{}"))
            }
            return LLMResponse(modelUsed: "x", stopReason: .toolUse, content: calls)
        }
        let chain = LLMChain(providers: [ScriptedProvider([batch("a"), batch("b"), batch("c")])])
        var registry = ToolRegistry()
        var invocations = 0
        registry.register(
            tool: LLMTool(name: "create_task", description: "x", inputSchema: #"{"type":"object"}"#),
            handler: { _ in
                invocations += 1
                return "{}"
            })
        let loop = ToolLoop(chain: chain, registry: registry,
                            maxIterations: 3,
                            maxToolCallsPerResponse: 8,
                            maxToolCallsPerRun: 10)
        let result = try await loop.run(initialMessages: [LLMMessage(role: .user, content: [.text("x")])])
        XCTAssertEqual(invocations, 6)
        XCTAssertTrue(result.text.contains("refused"))
    }

    func testThrownInvocationCountsAgainstTheRunBudget() async throws {
        let call = LLMResponse(modelUsed: "x", stopReason: .toolUse,
                               content: [.toolUse(ToolCall(id: "c", name: "echo", argumentsJSON: "{}"))])
        let chain = LLMChain(providers: [ScriptedProvider([call, call])])
        var registry = ToolRegistry()
        var invocations = 0
        registry.register(
            tool: LLMTool(name: "echo", description: "x", inputSchema: #"{"type":"object"}"#),
            handler: { _ in
                invocations += 1
                throw NSError(domain: "test", code: 1)
            })
        let loop = ToolLoop(chain: chain, registry: registry,
                            maxIterations: 2,
                            maxToolCallsPerRun: 1)
        let result = try await loop.run(initialMessages: [LLMMessage(role: .user, content: [.text("x")])])
        XCTAssertEqual(invocations, 1)
        XCTAssertTrue(result.text.contains("refused"))
    }
}
