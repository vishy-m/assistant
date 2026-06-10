import XCTest
@testable import AssistantLLM

final class OpenAIProviderTests: XCTestCase {

    func testTextResponse() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "model": "gpt-4o",
          "choices": [{
            "finish_reason": "stop",
            "message": { "role": "assistant", "content": "Hi there." }
          }]
        }
        """)
        let provider = OpenAIProvider(http: http, apiKeyProvider: { "sk-test" })
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("hi")])],
            tools: [])
        XCTAssertEqual(resp.text, "Hi there.")
        XCTAssertEqual(resp.stopReason, .endTurn)
    }

    func testToolCallResponse() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "model": "gpt-4o",
          "choices": [{
            "finish_reason": "tool_calls",
            "message": {
              "role": "assistant",
              "content": null,
              "tool_calls": [{
                "id": "call_1",
                "type": "function",
                "function": { "name": "create_task", "arguments": "{\\"title\\":\\"X\\"}" }
              }]
            }
          }]
        }
        """)
        let provider = OpenAIProvider(http: http, apiKeyProvider: { "sk-test" })
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("add a task")])],
            tools: [LLMTool(name: "create_task", description: "x",
                            inputSchema: #"{"type":"object"}"#)])
        XCTAssertEqual(resp.stopReason, .toolUse)
        XCTAssertEqual(resp.toolCalls.first?.argumentsJSON, #"{"title":"X"}"#)
    }

    func testRateLimited() async {
        let http = MockHTTPClient()
        http.enqueueJSON("{}", status: 429)
        let provider = OpenAIProvider(http: http, apiKeyProvider: { "sk-test" })
        do {
            _ = try await provider.complete(messages: [LLMMessage(role: .user, content: [.text("x")])], tools: [])
            XCTFail()
        } catch ProviderError.rateLimited {} catch { XCTFail("\(error)") }
    }
}
