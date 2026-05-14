import Foundation

public final class ClaudeProvider: LLMProvider {

    public let name = "claude"

    private let http: HTTPClient
    private let apiKeyProvider: @Sendable () -> String?
    private let model: String
    private let endpoint: URL

    public init(http: HTTPClient,
                apiKeyProvider: @escaping @Sendable () -> String?,
                model: String = "claude-sonnet-4-6",
                endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!) {
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
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = body

        let resp: HTTPResponse
        do {
            resp = try await http.send(req)
        } catch {
            throw ProviderError.transient(message: "\(error)")
        }

        try mapStatus(resp.statusCode, data: resp.data)
        return try decode(resp.data)
    }

    // MARK: - Encoding

    private func makeBody(messages: [LLMMessage], tools: [LLMTool]) throws -> Data {
        var dict: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": messages.map { makeMessageDict($0) }
        ]
        if !tools.isEmpty {
            dict["tools"] = try tools.map { t -> [String: Any] in
                let schemaObj = try JSONSerialization.jsonObject(with: t.inputSchema.data(using: .utf8) ?? Data())
                return ["name": t.name, "description": t.description, "input_schema": schemaObj]
            }
        }
        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }

    private func makeMessageDict(_ m: LLMMessage) -> [String: Any] {
        let contentArr: [[String: Any]] = m.content.compactMap { block -> [String: Any]? in
            switch block {
            case .text(let t):
                return ["type": "text", "text": t]
            case .image(let img):
                return ["type": "image",
                        "source": ["type": "base64",
                                   "media_type": img.mediaType,
                                   "data": img.data.base64EncodedString()]]
            case .toolUse(let tc):
                let argsObj = (try? JSONSerialization.jsonObject(with: tc.argumentsJSON.data(using: .utf8) ?? Data())) ?? [:]
                return ["type": "tool_use", "id": tc.id, "name": tc.name, "input": argsObj]
            case .toolResult(let id, let content):
                return ["type": "tool_result", "tool_use_id": id, "content": content]
            }
        }
        return ["role": m.role == .assistant ? "assistant" : "user",
                "content": contentArr]
    }

    // MARK: - Decoding

    private func mapStatus(_ status: Int, data: Data) throws {
        switch status {
        case 200..<300: return
        case 429: throw ProviderError.rateLimited
        case 529: throw ProviderError.serverOverloaded
        case 500..<600: throw ProviderError.transient(message: "HTTP \(status)")
        default:
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.clientError(statusCode: status, message: msg)
        }
    }

    private func decode(_ data: Data) throws -> LLMResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decodingFailure(message: "not a JSON object")
        }
        let modelStr = root["model"] as? String ?? model
        let stopStr = root["stop_reason"] as? String ?? "end_turn"
        let stop = LLMStopReason(rawValue: stopStr) ?? .endTurn

        var blocks: [LLMContentBlock] = []
        let contentArr = root["content"] as? [[String: Any]] ?? []
        for c in contentArr {
            let type = c["type"] as? String ?? ""
            switch type {
            case "text":
                if let t = c["text"] as? String { blocks.append(.text(t)) }
            case "tool_use":
                let id = c["id"] as? String ?? UUID().uuidString
                let n = c["name"] as? String ?? ""
                let inputObj = c["input"] as? [String: Any] ?? [:]
                let inputData = (try? JSONSerialization.data(withJSONObject: inputObj)) ?? Data()
                let inputStr = String(data: inputData, encoding: .utf8) ?? "{}"
                blocks.append(.toolUse(ToolCall(id: id, name: n, argumentsJSON: inputStr)))
            default:
                continue
            }
        }
        return LLMResponse(modelUsed: modelStr, stopReason: stop, content: blocks)
    }
}
