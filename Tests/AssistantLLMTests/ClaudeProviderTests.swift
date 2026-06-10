import XCTest
@testable import AssistantLLM

final class ClaudeProviderTests: XCTestCase {

    func testTextResponseDecoded() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "id": "msg_1",
          "model": "claude-sonnet-4-6",
          "stop_reason": "end_turn",
          "content": [
            { "type": "text", "text": "Hello!" }
          ]
        }
        """)
        let provider = ClaudeProvider(http: http, apiKeyProvider: { "sk-test" })
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("hi")])],
            tools: [])
        XCTAssertEqual(resp.modelUsed, "claude-sonnet-4-6")
        XCTAssertEqual(resp.stopReason, .endTurn)
        XCTAssertEqual(resp.text, "Hello!")
    }

    func testToolUseResponseDecoded() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "id": "msg_2",
          "model": "claude-sonnet-4-6",
          "stop_reason": "tool_use",
          "content": [
            { "type": "tool_use", "id": "call_1", "name": "create_task",
              "input": { "title": "X" } }
          ]
        }
        """)
        let provider = ClaudeProvider(http: http, apiKeyProvider: { "sk-test" })
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("add a task")])],
            tools: [LLMTool(name: "create_task", description: "Add task",
                            inputSchema: #"{"type":"object","properties":{"title":{"type":"string"}}}"#)])
        XCTAssertEqual(resp.stopReason, .toolUse)
        XCTAssertEqual(resp.toolCalls.first?.name, "create_task")
        XCTAssertEqual(resp.toolCalls.first?.argumentsJSON, #"{"title":"X"}"#)
    }

    func testNotConfiguredThrows() async {
        let http = MockHTTPClient()
        let provider = ClaudeProvider(http: http, apiKeyProvider: { nil })
        do {
            _ = try await provider.complete(messages: [], tools: [])
            XCTFail("expected throw")
        } catch ProviderError.notConfigured {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRateLimitedMapsTo429() async {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"type":"error","error":{"type":"rate_limit_error"}}"#, status: 429)
        let provider = ClaudeProvider(http: http, apiKeyProvider: { "sk-test" })
        do {
            _ = try await provider.complete(messages: [LLMMessage(role: .user, content: [.text("x")])],
                                            tools: [])
            XCTFail("expected throw")
        } catch ProviderError.rateLimited {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
