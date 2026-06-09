import XCTest
@testable import AssistantLLM

final class GemmaHostedProviderTests: XCTestCase {

    func testTextResponse() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "candidates": [{
            "content": { "role": "model", "parts": [{ "text": "ok" }] },
            "finishReason": "STOP"
          }]
        }
        """)
        let provider = GemmaHostedProvider(http: http, apiKeyProvider: { "key" })
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("hi")])],
            tools: [])
        XCTAssertEqual(resp.text, "ok")
    }

    func testFunctionCallResponse() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "candidates": [{
            "content": { "role": "model", "parts": [{
              "functionCall": { "name": "create_task", "args": { "title": "X" } }
            }] },
            "finishReason": "STOP"
          }]
        }
        """)
        let provider = GemmaHostedProvider(http: http, apiKeyProvider: { "key" })
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("add a task")])],
            tools: [LLMTool(name: "create_task", description: "x", inputSchema: #"{"type":"object"}"#)])
        XCTAssertEqual(resp.stopReason, .toolUse)
        XCTAssertEqual(resp.toolCalls.first?.name, "create_task")
    }
}
