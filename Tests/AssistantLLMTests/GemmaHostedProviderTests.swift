import XCTest
@testable import AssistantLLM

final class GemmaHostedProviderTests: XCTestCase {

    func testSystemInstructionAndFunctionResponseEncoding() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#)
        let provider = GemmaHostedProvider(http: http, apiKeyProvider: { "key" })
        _ = try await provider.complete(messages: [
            LLMMessage(role: .system, content: [.text("Be helpful")]),
            LLMMessage(role: .user, content: [.text("Do it")]),
            LLMMessage(role: .assistant, content: [
                .toolUse(ToolCall(id: "c1", name: "create_task", argumentsJSON: "{}"))
            ]),
            LLMMessage(role: .tool, content: [.toolResult(toolCallId: "c1", content: "done")])
        ], tools: [])
        let request = try XCTUnwrap(http.sentRequests.first)
        XCTAssertEqual(request.url?.path, "/v1beta/models/gemma-4-31b-it:generateContent")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let system = body["systemInstruction"] as? [String: Any]
        XCTAssertEqual((system?["parts"] as? [[String: String]])?.first?["text"], "Be helpful")
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 3)
        let parts = try XCTUnwrap(contents.last?["parts"] as? [[String: Any]])
        let response = try XCTUnwrap(parts.first?["functionResponse"] as? [String: Any])
        XCTAssertEqual(response["name"] as? String, "create_task")
        XCTAssertEqual(response["id"] as? String, "c1")
        XCTAssertEqual(provider.name, "gemma_hosted")
    }

    func testFunctionCallPreservesSuppliedID() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"candidates":[{"content":{"parts":[{"functionCall":{"id":"google-call-1","name":"echo","args":{}}}]}}]}"#)
        let provider = GemmaHostedProvider(http: http, apiKeyProvider: { "key" })
        let response = try await provider.complete(messages: [], tools: [])
        XCTAssertEqual(response.toolCalls.first?.id, "google-call-1")
    }

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
