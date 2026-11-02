import XCTest
@testable import AssistantLLM

final class GeminiProviderTests: XCTestCase {
    private let textResponse = #"{"candidates":[{"content":{"role":"model","parts":[{"text":"done"}]},"finishReason":"STOP"}]}"#
    private let parallelResponse = #"{"candidates":[{"content":{"role":"model","parts":[{"text":"Checking"},{"functionCall":{"id":"call-1","name":"echo","args":{"value":1}},"thoughtSignature":"opaque+/signature=="},{"functionCall":{"id":"call-2","name":"echo","args":{"value":2}}}]},"finishReason":"STOP"}]}"#

    private func body(_ http: MockHTTPClient, at index: Int = 0) throws -> [String: Any] {
        let data = try XCTUnwrap(http.sentRequests[index].httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDefaultModelAndHeaderAuthentication() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(textResponse)
        let provider = GeminiProvider(http: http, apiKeyProvider: { "secret-test-key" })
        let response = try await provider.complete(messages: [
            LLMMessage(role: .user, content: [.text("hi")])
        ], tools: [])
        let request = try XCTUnwrap(http.sentRequests.first)
        XCTAssertEqual(provider.name, "gemini")
        XCTAssertEqual(response.modelUsed, GeminiProvider.defaultModel)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiProvider.defaultModel):generateContent")
        XCTAssertNil(request.url?.query)
        XCTAssertFalse(request.url!.absoluteString.contains("secret-test-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret-test-key")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testThoughtSignatureRoundTripAndSeparateToolMessages() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(parallelResponse)
        http.enqueueJSON(textResponse)
        let provider = GeminiProvider(http: http, apiKeyProvider: { "key" })
        let prompt = LLMMessage(role: .user, content: [.text("echo twice")])
        let response = try await provider.complete(messages: [prompt], tools: [])
        XCTAssertEqual(response.toolCalls.map(\.id), ["call-1", "call-2"])
        XCTAssertEqual(response.toolCalls.first?.thoughtSignature, "opaque+/signature==")
        XCTAssertNil(response.toolCalls.last?.thoughtSignature)
        // Persisted conversation history must retain the signature, too.
        let assistant = try JSONDecoder().decode(LLMMessage.self, from: JSONEncoder().encode(
            LLMMessage(role: .assistant, content: response.content)))
        _ = try await provider.complete(messages: [prompt, assistant,
            LLMMessage(role: .tool, content: [.toolResult(toolCallId: "call-1", content: "one")]),
            LLMMessage(role: .tool, content: [.toolResult(toolCallId: "call-2", content: "two")])
        ], tools: [])
        let contents = try XCTUnwrap(try body(http, at: 1)["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 3)
        let modelParts = try XCTUnwrap(contents[1]["parts"] as? [[String: Any]])
        XCTAssertEqual(modelParts.count, 3)
        XCTAssertNil(modelParts[0]["thoughtSignature"])
        XCTAssertEqual(modelParts[1]["thoughtSignature"] as? String, "opaque+/signature==")
        XCTAssertNil(modelParts[2]["thoughtSignature"])
        XCTAssertEqual((modelParts[1]["functionCall"] as? [String: Any])?["id"] as? String, "call-1")
        XCTAssertEqual(contents[2]["role"] as? String, "user")
        let resultParts = try XCTUnwrap(contents[2]["parts"] as? [[String: Any]])
        XCTAssertEqual(resultParts.count, 2)
        for (index, part) in resultParts.enumerated() {
            let result = try XCTUnwrap(part["functionResponse"] as? [String: Any])
            XCTAssertEqual(result["name"] as? String, "echo")
            XCTAssertEqual(result["id"] as? String, "call-\(index + 1)")
            XCTAssertEqual((result["response"] as? [String: String])?["result"], index == 0 ? "one" : "two")
        }
    }

    func testToolLoopParallelResultsAndSystemInstructions() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(parallelResponse)
        http.enqueueJSON(textResponse)
        let provider = GeminiProvider(http: http, apiKeyProvider: { "key" })
        var registry = ToolRegistry()
        registry.register(tool: LLMTool(name: "echo", description: "Echo", inputSchema: #"{"type":"object"}"#),
                          handler: { $0 })
        let loop = ToolLoop(chain: LLMChain(providers: [provider]), registry: registry)
        let response = try await loop.run(initialMessages: [
            LLMMessage(role: .system, content: [.text("Be helpful")]),
            LLMMessage(role: .system, content: [.text("Be concise")]),
            LLMMessage(role: .user, content: [.text("echo twice")])
        ])
        XCTAssertEqual(response.text, "done")
        let request = try body(http, at: 1)
        let system = try XCTUnwrap(request["systemInstruction"] as? [String: Any])
        XCTAssertEqual(system["parts"] as? [[String: String]], [["text": "Be helpful"], ["text": "Be concise"]])
        let contents = try XCTUnwrap(request["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.compactMap { $0["role"] as? String }, ["user", "model", "user"])
        let parts = try XCTUnwrap(contents.last?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.compactMap { ($0["functionResponse"] as? [String: Any])?["id"] as? String },
                       ["call-1", "call-2"])
        let modelParts = try XCTUnwrap(contents[1]["parts"] as? [[String: Any]])
        XCTAssertEqual(modelParts[1]["thoughtSignature"] as? String, "opaque+/signature==")
        let toolGroups = try XCTUnwrap(request["tools"] as? [[String: Any]])
        let declarations = try XCTUnwrap(toolGroups.first?["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.first?["name"] as? String, "echo")
    }

    func testBlockedAndEmptyResponsesHaveClearErrorsForBothProviders() async {
        let fixtures = [
            (#"{"promptFeedback":{"blockReason":"SAFETY"}}"#, "SAFETY"),
            (#"{"candidates":[{"finishReason":"SAFETY"}]}"#, "SAFETY"),
            (#"{"candidates":[{"finishReason":"RECITATION","content":{"parts":[{"text":"partial"}]}}]}"#, "RECITATION"),
            (#"{"candidates":[]}"#, "no candidates"),
            (#"{}"#, "no candidates"),
            (#"{"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}"#, "no usable content")
        ]
        for (json, reason) in fixtures {
            for isGemini in [true, false] {
                let http = MockHTTPClient()
                http.enqueueJSON(json)
                let provider: any LLMProvider = isGemini
                    ? GeminiProvider(http: http, apiKeyProvider: { "key" })
                    : GemmaHostedProvider(http: http, apiKeyProvider: { "key" })
                do {
                    _ = try await provider.complete(messages: [], tools: [])
                    XCTFail("Expected rejection for \(json)")
                } catch ProviderError.responseRejected(let message) {
                    XCTAssertTrue(message.contains(reason), message)
                    XCTAssertTrue(message.contains(provider.name), message)
                } catch { XCTFail("Expected clear response rejection, got \(error)") }
            }
        }
    }

    func testHTTPStatusMapping() async {
        for (status, expected) in [(429, ProviderError.rateLimited),
                                   (503, .transient(message: "HTTP 503")),
                                   (400, .clientError(statusCode: 400, message: "bad"))] {
            let http = MockHTTPClient()
            http.enqueueJSON("bad", status: status)
            do {
                _ = try await GeminiProvider(http: http, apiKeyProvider: { "key" }).complete(messages: [], tools: [])
                XCTFail("Expected HTTP error")
            } catch { XCTAssertEqual(error as? ProviderError, expected) }
        }
    }

    func testMissingKeySkipsRequest() async {
        let http = MockHTTPClient()
        let provider = GeminiProvider(http: http, apiKeyProvider: { nil })
        XCTAssertFalse(provider.isConfigured())
        do {
            _ = try await provider.complete(messages: [], tools: [])
            XCTFail("Expected not configured")
        } catch { XCTAssertEqual(error as? ProviderError, .notConfigured) }
        XCTAssertTrue(http.sentRequests.isEmpty)
    }

    func testMissingFunctionCallIDGetsUUID() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"echo","args":{}}}]}}]}"#)
        let response = try await GeminiProvider(http: http, apiKeyProvider: { "key" }).complete(messages: [], tools: [])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(response.toolCalls.first?.id)))
    }

    func testToolCallDecodesLegacyJSON() throws {
        let data = Data(#"{"id":"legacy","name":"echo","argumentsJSON":"{}"}"#.utf8)
        let call = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(call.id, "legacy")
        XCTAssertEqual(call.name, "echo")
        XCTAssertEqual(call.argumentsJSON, "{}")
        XCTAssertNil(call.thoughtSignature)
    }
    func testLocallyGeneratedIDsAreNotSentBack() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"echo","args":{}}}]}}]}"#)
        http.enqueueJSON(textResponse)
        let provider = GeminiProvider(http: http, apiKeyProvider: { "key" })
        let prompt = LLMMessage(role: .user, content: [.text("hi")])
        let response = try await provider.complete(messages: [prompt], tools: [])
        let callID = try XCTUnwrap(response.toolCalls.first?.id)
        _ = try await provider.complete(messages: [
            prompt,
            LLMMessage(role: .assistant, content: response.content),
            LLMMessage(role: .user, content: [.toolResult(toolCallId: callID, content: "ok")])
        ], tools: [])
        let contents = try XCTUnwrap(try body(http, at: 1)["contents"] as? [[String: Any]])
        let call = try XCTUnwrap((contents[1]["parts"] as? [[String: Any]])?.first?["functionCall"] as? [String: Any])
        let result = try XCTUnwrap((contents[2]["parts"] as? [[String: Any]])?.first?["functionResponse"] as? [String: Any])
        XCTAssertNil(call["id"], "Gemini never issued this id")
        XCTAssertNil(result["id"])
        XCTAssertEqual(call["name"] as? String, "echo")
        XCTAssertEqual(result["name"] as? String, "echo")
    }

    /// A tool turn produced by another tier (e.g. Claude, before it hit a rate
    /// limit) has no thought signature. Gemini 3 rejects an unsigned first
    /// functionCall in the current turn, so Gemini sends the documented
    /// validator-skip signature on it; Gemma gets the history unchanged.
    func testForeignToolCallsGetSkipSignatureOnGeminiOnly() async throws {
        let history = [
            LLMMessage(role: .user, content: [.text("echo twice")]),
            LLMMessage(role: .assistant, content: [
                .toolUse(ToolCall(id: "toolu_1", name: "echo", argumentsJSON: "{}")),
                .toolUse(ToolCall(id: "toolu_2", name: "echo", argumentsJSON: "{}"))
            ]),
            LLMMessage(role: .user, content: [.toolResult(toolCallId: "toolu_1", content: "a"),
                                              .toolResult(toolCallId: "toolu_2", content: "b")])
        ]
        for isGemini in [true, false] {
            let http = MockHTTPClient()
            http.enqueueJSON(textResponse)
            let provider: any LLMProvider = isGemini
                ? GeminiProvider(http: http, apiKeyProvider: { "key" })
                : GemmaHostedProvider(http: http, apiKeyProvider: { "key" })
            _ = try await provider.complete(messages: history, tools: [])
            let contents = try XCTUnwrap(try body(http)["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents[1]["parts"] as? [[String: Any]])
            XCTAssertEqual(parts[0]["thoughtSignature"] as? String,
                           isGemini ? GoogleGenerativeLanguageProvider.skipThoughtSignature : nil)
            XCTAssertNil(parts[1]["thoughtSignature"])
        }
    }
}
