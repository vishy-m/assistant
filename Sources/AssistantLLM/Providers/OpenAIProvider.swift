import Foundation

public final class OpenAIProvider: LLMProvider {

    public let name = "openai"

    private let http: HTTPClient
    private let apiKeyProvider: @Sendable () -> String?
    private let model: String
    private let endpoint: URL

    public init(http: HTTPClient,
                apiKeyProvider: @escaping @Sendable () -> String?,
                model: String = "gpt-4o",
                endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) {
        self.http = http
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.endpoint = endpoint
    }

    public func isConfigured() -> Bool { apiKeyProvider() != nil }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        guard let key = apiKeyProvider() else { throw ProviderError.notConfigured }

        let body = try makeBody(messages: messages, tools: tools)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let resp: HTTPResponse
        do { resp = try await http.send(req) } catch { throw ProviderError.transient(message: "\(error)") }

        switch resp.statusCode {
        case 200..<300: break
        case 429: throw ProviderError.rateLimited
        case 500..<600: throw ProviderError.transient(message: "HTTP \(resp.statusCode)")
        default:
            throw ProviderError.clientError(statusCode: resp.statusCode,
                                            message: String(data: resp.data, encoding: .utf8) ?? "")
        }

        return try decode(resp.data)
    }

    private func makeBody(messages: [LLMMessage], tools: [LLMTool]) throws -> Data {
        var dict: [String: Any] = [
            "model": model,
            "messages": messages.map { makeOpenAIMessage($0) }
        ]
        if !tools.isEmpty {
            dict["tools"] = try tools.map { t -> [String: Any] in
                let schemaObj = try JSONSerialization.jsonObject(with: t.inputSchema.data(using: .utf8) ?? Data())
                return ["type": "function",
                        "function": ["name": t.name,
                                     "description": t.description,
                                     "parameters": schemaObj]]
            }
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func makeOpenAIMessage(_ m: LLMMessage) -> [String: Any] {
        // OpenAI uses string content for text-only, array for multimodal.
        let hasImage = m.content.contains { if case .image = $0 { return true } else { return false } }
        let role: String = {
            switch m.role {
            case .user: return "user"
            case .assistant: return "assistant"
            case .system: return "system"
            case .tool: return "tool"
            }
        }()
        if !hasImage, let only = m.content.first, case .text(let t) = only, m.content.count == 1 {
            return ["role": role, "content": t]
        }
        let parts: [[String: Any]] = m.content.compactMap { block -> [String: Any]? in
            switch block {
            case .text(let t):
                return ["type": "text", "text": t]
            case .image(let img):
                let b64 = img.data.base64EncodedString()
                return ["type": "image_url",
                        "image_url": ["url": "data:\(img.mediaType);base64,\(b64)"]]
            case .toolUse, .toolResult:
                return nil  // OpenAI represents these at message level, not content level
            }
        }
        return ["role": role, "content": parts]
    }

    private func decode(_ data: Data) throws -> LLMResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw ProviderError.decodingFailure(message: "missing choices/message")
        }
        let modelStr = root["model"] as? String ?? model
        let finish = first["finish_reason"] as? String ?? "stop"

        var blocks: [LLMContentBlock] = []
        if let text = message["content"] as? String, !text.isEmpty {
            blocks.append(.text(text))
        }
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                let id = tc["id"] as? String ?? UUID().uuidString
                if let fn = tc["function"] as? [String: Any],
                   let name = fn["name"] as? String,
                   let args = fn["arguments"] as? String {
                    blocks.append(.toolUse(ToolCall(id: id, name: name, argumentsJSON: args)))
                }
            }
        }
        let stop: LLMStopReason = (finish == "tool_calls") ? .toolUse : .endTurn
        return LLMResponse(modelUsed: modelStr, stopReason: stop, content: blocks)
    }
}
