import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM

NSLog("[AssistantCoreHelper] starting")

let db: AssistantDB
do {
    db = try AssistantDB(fileURL: try AssistantDB.defaultFileURL())
} catch {
    NSLog("[AssistantCoreHelper] FATAL: \(error)")
    exit(1)
}

// HTTP + Keychain
let http: HTTPClient = URLSessionHTTPClient()
let keychain = KeychainStore()

// Providers — each reads its key lazily so the user can configure later without restart.
let claude = ClaudeProvider(http: http,
                            apiKeyProvider: { try? keychain.get(.claudeAPIKey) })
let openai = OpenAIProvider(http: http,
                            apiKeyProvider: { try? keychain.get(.openaiAPIKey) })
let gemmaHosted = GemmaHostedProvider(http: http,
                                      apiKeyProvider: { try? keychain.get(.gemmaHostedAPIKey) })
let ollama = OllamaLocalProvider(http: http)

let chain = LLMChain(providers: [claude, openai, gemmaHosted, ollama])

// Tool registry
var registry = ToolRegistry()
BuiltinTools.registerTaskTools(into: &registry,
                               taskRepo: TaskRepository(db: db),
                               gcalRepo: GCalRepository(db: db))

let loop = ToolLoop(chain: chain, registry: registry)
let service = AssistantService(db: db, loop: loop)

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: AssistantService
    init(service: AssistantService) { self.service = service }
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
        conn.exportedObject = service
        conn.resume()
        return true
    }
}

let delegate = ListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: XPCConstants.machServiceName)
listener.delegate = delegate
listener.resume()
NSLog("[AssistantCoreHelper] listener resumed")
RunLoop.main.run()
