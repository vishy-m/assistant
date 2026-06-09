import XCTest
@testable import AssistantLLM

final class OllamaLocalProviderTests: XCTestCase {

    func testTextResponse() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "model": "gemma4:e2b",
          "message": { "role": "assistant", "content": "hello" },
          "done": true
        }
        """)
        let provider = OllamaLocalProvider(http: http)
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("hi")])],
            tools: [])
        XCTAssertEqual(resp.text, "hello")
    }

    func testToolCallResponse() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {
          "model": "gemma4:e2b",
          "message": {
            "role": "assistant",
            "content": "",
            "tool_calls": [{
              "function": { "name": "create_task", "arguments": { "title": "X" } }
            }]
          },
          "done": true
        }
        """)
        let provider = OllamaLocalProvider(http: http)
        let resp = try await provider.complete(
            messages: [LLMMessage(role: .user, content: [.text("add task")])],
            tools: [LLMTool(name: "create_task", description: "x",
                            inputSchema: #"{"type":"object"}"#)])
        XCTAssertEqual(resp.stopReason, .toolUse)
        XCTAssertEqual(resp.toolCalls.first?.name, "create_task")
    }

    func testConnectionRefusedMapsToTransient() async {
        let http = MockHTTPClient()
        http.enqueue(.failure(URLError(.cannotConnectToHost)))
        let provider = OllamaLocalProvider(http: http)
        do {
            _ = try await provider.complete(messages: [], tools: [])
            XCTFail()
        } catch ProviderError.transient {} catch { XCTFail("\(error)") }
    }
}
