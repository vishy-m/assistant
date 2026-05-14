import Foundation

public final class OllamaLocalProvider: LLMProvider {

    public let name = "gemma_local"

    private let http: HTTPClient
    private let model: String
    private let endpoint: URL

    public init(http: HTTPClient,
                model: String = "gemma4:e2b",
                endpoint: URL = URL(string: "http://localhost:11434/api/chat")!) {
        self.http = http
        self.model = model
        self.endpoint = endpoint
    }

    /// Always "configured" — local. Failure to reach Ollama surfaces as a transient error.
    public func isConfigured() -> Bool { true }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        let body = try makeBody(messages: messages, tools: tools)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30

        let resp: HTTPResponse
        do { resp = try await http.send(req) } catch { throw ProviderError.transient(message: "\(error)") }

        guard (200..<300).contains(resp.statusCode) else {
            throw ProviderError.transient(message: "Ollama HTTP \(resp.statusCode)")
        }
        return try decode(resp.data)
    }

    private func makeBody(messages: [LLMMessage], tools: [LLMTool]) throws -> Data {
        let msgs = messages.map { m -> [String: Any] in
            let role: String = {
                switch m.role {
                case .user: return "user"
                case .assistant: return "assistant"
                case .system: return "system"
                case .tool: return "tool"
                }
            }()
            var content = ""
            var images: [String] = []
            for block in m.content {
                switch block {
                case .text(let t): content += t
                case .image(let img): images.append(img.data.base64EncodedString())
                case .toolUse, .toolResult: break
                }
            }
            var dict: [String: Any] = ["role": role, "content": content]
            if !images.isEmpty { dict["images"] = images }
            return dict
        }

        var dict: [String: Any] = [
            "model": model,
            "messages": msgs,
            "stream": false
        ]
        if !tools.isEmpty {
            dict["tools"] = try tools.map { t -> [String: Any] in
                let schemaObj = try JSONSerialization.jsonObject(with: t.inputSchema.data(using: .utf8) ?? Data())
                return ["type": "function",
                        "function": ["name": t.name, "description": t.description, "parameters": schemaObj]]
            }
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func decode(_ data: Data) throws -> LLMResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any] else {
            throw ProviderError.decodingFailure(message: "missing message")
        }
        let modelStr = root["model"] as? String ?? model
        var blocks: [LLMContentBlock] = []
        if let text = message["content"] as? String, !text.isEmpty { blocks.append(.text(text)) }
        var sawTool = false
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                if let fn = tc["function"] as? [String: Any],
                   let name = fn["name"] as? String {
                    let args = fn["arguments"] as? [String: Any] ?? [:]
                    let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                    let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                    blocks.append(.toolUse(ToolCall(id: UUID().uuidString, name: name, argumentsJSON: argsStr)))
                    sawTool = true
                }
            }
        }
        return LLMResponse(modelUsed: modelStr,
                           stopReason: sawTool ? .toolUse : .endTurn,
                           content: blocks)
    }
}
