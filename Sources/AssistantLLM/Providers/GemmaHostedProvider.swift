import Foundation

public final class GemmaHostedProvider: LLMProvider {

    public let name = "gemma_hosted"

    private let http: HTTPClient
    private let apiKeyProvider: @Sendable () -> String?
    private let model: String

    public init(http: HTTPClient,
                apiKeyProvider: @escaping @Sendable () -> String?,
                model: String = "gemma-4-31b-it") {
        self.http = http
        self.apiKeyProvider = apiKeyProvider
        self.model = model
    }

    public func isConfigured() -> Bool { apiKeyProvider() != nil }

    public func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
        guard let key = apiKeyProvider() else { throw ProviderError.notConfigured }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!

        let body = try makeBody(messages: messages, tools: tools)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        let contents = messages.map { m -> [String: Any] in
            let role = (m.role == .assistant) ? "model" : "user"
            let parts: [[String: Any]] = m.content.compactMap { block in
                switch block {
                case .text(let t): return ["text": t]
                case .image(let img):
                    return ["inline_data": ["mime_type": img.mediaType,
                                            "data": img.data.base64EncodedString()]]
                case .toolUse(let tc):
                    let argsObj = (try? JSONSerialization.jsonObject(with: tc.argumentsJSON.data(using: .utf8) ?? Data())) ?? [:]
                    return ["functionCall": ["name": tc.name, "args": argsObj]]
                case .toolResult(_, let content):
                    return ["functionResponse": ["name": "tool", "response": ["result": content]]]
                }
            }
            return ["role": role, "parts": parts]
        }
        var dict: [String: Any] = ["contents": contents]
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
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw ProviderError.decodingFailure(message: "missing candidates/content/parts")
        }
        var blocks: [LLMContentBlock] = []
        var sawToolUse = false
        for p in parts {
            if let t = p["text"] as? String { blocks.append(.text(t)) }
            if let fc = p["functionCall"] as? [String: Any],
               let name = fc["name"] as? String {
                let args = fc["args"] as? [String: Any] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                blocks.append(.toolUse(ToolCall(id: UUID().uuidString, name: name, argumentsJSON: argsStr)))
                sawToolUse = true
            }
        }
        return LLMResponse(modelUsed: model,
                           stopReason: sawToolUse ? .toolUse : .endTurn,
                           content: blocks)
    }
}
