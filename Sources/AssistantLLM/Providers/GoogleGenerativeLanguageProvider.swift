import Foundation

/// Shared client for Google's Generative Language API (`generateContent`),
/// used by both the Gemini and hosted Gemma tiers.
final class GoogleGenerativeLanguageProvider: LLMProvider {

    /// Google's documented placeholder signature for function calls the model
    /// didn't produce itself (here: tool turns from another tier in the chain).
    /// Gemini 3+ rejects an unsigned first functionCall in the current turn.
    static let skipThoughtSignature = "skip_thought_signature_validator"

    let name: String

    private let http: HTTPClient
    private let apiKeyProvider: @Sendable () -> String?
    private let model: String
    private let signsForeignFunctionCalls: Bool

    init(name: String, http: HTTPClient,
         apiKeyProvider: @escaping @Sendable () -> String?,
         model: String,
         signsForeignFunctionCalls: Bool = false) {
        self.name = name
        self.http = http
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.signsForeignFunctionCalls = signsForeignFunctionCalls
    }

    /// Ids we made up (UUIDs) for calls Google returned without one are kept
    /// local; only ids the API (or another provider) issued are sent back.
    private static func wireID(_ id: String) -> String? {
        UUID(uuidString: id) == nil ? id : nil
    }

    public func isConfigured() -> Bool { apiKeyProvider() != nil }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        guard let key = apiKeyProvider() else { throw ProviderError.notConfigured }
        // Key goes in a header, never the URL — a key in a query string leaks
        // into logs, URLError descriptions, and proxy access logs.
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        let body = try makeBody(messages: messages, tools: tools)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = body

        let resp: HTTPResponse
        do { resp = try await http.send(req) } catch { throw ProviderError.transient(message: "\(error)") }

        switch resp.statusCode {
        case 200..<300: break
        case 429: throw ProviderError.rateLimited
        case 500..<600: throw ProviderError.transient(message: "HTTP \(resp.statusCode)")
        default: throw ProviderError.clientError(statusCode: resp.statusCode,
                                                 message: String(data: resp.data, encoding: .utf8) ?? "")
        }
        return try decode(resp.data)
    }

    private func makeBody(messages: [LLMMessage], tools: [LLMTool]) throws -> Data {
        var contents: [[String: Any]] = []
        var systemParts: [[String: Any]] = []
        var callsByID: [String: ToolCall] = [:]
        var previousWasToolResults = false
        for message in messages {
            if message.role == .system {
                systemParts += message.content.compactMap { block in
                    if case .text(let text) = block { return ["text": text] }
                    return nil
                }
                continue
            }
            let role = message.role == .assistant ? "model" : "user"
            var sawFunctionCall = false
            let parts: [[String: Any]] = try message.content.map { block in
                switch block {
                case .text(let text): return ["text": text]
                case .image(let image):
                    return ["inline_data": ["mime_type": image.mediaType,
                                            "data": image.data.base64EncodedString()]]
                case .toolUse(let call):
                    callsByID[call.id] = call
                    let args = try JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))
                    var functionCall: [String: Any] = ["name": call.name, "args": args]
                    functionCall["id"] = Self.wireID(call.id)
                    var part: [String: Any] = ["functionCall": functionCall]
                    if let signature = call.thoughtSignature {
                        part["thoughtSignature"] = signature
                    } else if signsForeignFunctionCalls && !sawFunctionCall {
                        // Only the first functionCall of a turn carries a signature.
                        part["thoughtSignature"] = Self.skipThoughtSignature
                    }
                    sawFunctionCall = true
                    return part
                case .toolResult(let id, let content):
                    guard let call = callsByID[id] else {
                        throw ProviderError.clientError(statusCode: 400,
                                                        message: "\(name): no preceding functionCall for tool result \(id)")
                    }
                    var functionResponse: [String: Any] = ["name": call.name,
                                                           "response": ["result": content]]
                    functionResponse["id"] = Self.wireID(call.id)
                    return ["functionResponse": functionResponse]
                }
            }
            guard !parts.isEmpty else { continue }
            let isToolResults = role == "user" && message.content.allSatisfy {
                if case .toolResult = $0 { return true }
                return false
            }
            // ToolLoop already groups results. Also support histories with one
            // .tool message per result: parallel responses belong in one user turn.
            if isToolResults && previousWasToolResults {
                let last = contents.count - 1
                let previousParts = contents[last]["parts"] as? [[String: Any]] ?? []
                contents[last]["parts"] = previousParts + parts
            } else {
                contents.append(["role": role, "parts": parts])
            }
            previousWasToolResults = isToolResults
        }
        var dict: [String: Any] = ["contents": contents]
        if !systemParts.isEmpty {
            dict["systemInstruction"] = ["parts": systemParts]
        }
        if !tools.isEmpty {
            let decls = try tools.map { t -> [String: Any] in
                let schemaObj = try JSONSerialization.jsonObject(with: t.inputSchema.data(using: .utf8) ?? Data())
                return ["name": t.name, "description": t.description, "parameters": schemaObj]
            }
            dict["tools"] = [["functionDeclarations": decls]]
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func decode(_ data: Data) throws -> LLMResponse {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderError.decodingFailure(message: "\(name): invalid JSON response")
        }
        guard let root = object as? [String: Any] else {
            throw ProviderError.decodingFailure(message: "\(name): response is not a JSON object")
        }
        if let feedback = root["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String,
           reason != "BLOCK_REASON_UNSPECIFIED" {
            throw ProviderError.responseRejected(message: "\(name): prompt blocked (\(reason))")
        }
        guard let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first else {
            throw ProviderError.responseRejected(message: "\(name): response returned no candidates")
        }
        let finishReason = first["finishReason"] as? String
        if let reason = finishReason, !["STOP", "MAX_TOKENS", "FINISH_REASON_UNSPECIFIED"].contains(reason) {
            throw ProviderError.responseRejected(message: "\(name): generation stopped (\(reason))")
        }
        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw ProviderError.responseRejected(message: "\(name): response returned no usable content (\(finishReason ?? "unknown finish reason"))")
        }
        var blocks: [LLMContentBlock] = []
        var sawToolUse = false
        for p in parts {
            if let t = p["text"] as? String, !t.isEmpty, p["thought"] as? Bool != true {
                blocks.append(.text(t))
            }
            if let fc = p["functionCall"] as? [String: Any],
               let name = fc["name"] as? String {
                let args = fc["args"] as? [String: Any] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                blocks.append(.toolUse(ToolCall(id: fc["id"] as? String ?? UUID().uuidString,
                                               name: name, argumentsJSON: argsStr,
                                               thoughtSignature: p["thoughtSignature"] as? String)))
                sawToolUse = true
            }
        }
        guard !blocks.isEmpty else {
            throw ProviderError.responseRejected(message: "\(name): response returned no usable content (\(finishReason ?? "unknown finish reason"))")
        }
        return LLMResponse(modelUsed: model,
                           stopReason: sawToolUse ? .toolUse : (finishReason == "MAX_TOKENS" ? .maxTokens : .endTurn),
                           content: blocks)
    }
}
