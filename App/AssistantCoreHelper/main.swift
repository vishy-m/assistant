import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM
import AssistantGCal
import AssistantBriefings
import AssistantGrades

NSLog("[AssistantCoreHelper] starting")

let db: AssistantDB
do {
    db = try AssistantDB(fileURL: try AssistantDB.defaultFileURL())
} catch {
    NSLog("[AssistantCoreHelper] FATAL: \(error)")
    exit(1)
}

// Relocate any pre-Keychain Google OAuth client secret before anything reads it.
OAuthSecretMigration.run(db: db)

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

// MARK: - Google Calendar integration

// Let the token cache read OAuth client credentials from the settings table.
GCalAccessTokenCache.shared.configure(db: db)

let gcalClient = GCalClient(http: http,
                            accessTokenProvider: { GCalAccessTokenCache.shared.current() })
service.attachGCalClient(gcalClient)
let quota = QuotaGuard(db: db)
let syncWorker = GCalSyncWorker(client: gcalClient, db: db, quota: quota)
let outbox = OutboxProcessor(client: gcalClient, db: db, quota: quota)

// Register GCal tools into the existing registry, then rebuild + install the loop.
GCalTools.register(into: &registry, client: gcalClient, db: db)
GradeTools.register(into: &registry, db: db)
let loopWithGCal = ToolLoop(chain: chain, registry: registry)
service.replaceLoop(loopWithGCal)

// Every 5 minutes: sync events + drain outbox.
let gcalTimer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
gcalTimer.schedule(deadline: .now() + 10, repeating: .seconds(300))
gcalTimer.setEventHandler {
    _Concurrency.Task.detached {
        do { try await syncWorker.runOnce() } catch { NSLog("[Sync] error: \(error)") }
        do { try await outbox.drainOnce() } catch { NSLog("[Outbox] error: \(error)") }
    }
}
gcalTimer.resume()
NSLog("[AssistantCoreHelper] GCal sync timer started")

// MARK: - Briefing scheduler

let dispatcher = BriefingDispatcher(
    db: db,
    isFocused: { FocusModeMonitor().isFocused },
    pushToUI: { payload in service.pushBriefing(payload) })

let composer = BriefingComposer(chain: chain)
let rules = BriefingRules(db: db)
let scheduler = BriefingScheduler(db: db, dispatcher: dispatcher,
                                  composer: composer, rules: rules)

_Concurrency.Task.detached {
    await scheduler.start()
    NSLog("[BriefingScheduler] started")
}

// On Focus mode end, drain queue. Poll every 60s.
let focusPollTimer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
focusPollTimer.schedule(deadline: .now() + 60, repeating: .seconds(60))
nonisolated(unsafe) var lastFocused = FocusModeMonitor().isFocused
focusPollTimer.setEventHandler {
    let nowFocused = FocusModeMonitor().isFocused
    if lastFocused == true && nowFocused == false {
        _Concurrency.Task.detached {
            try? await dispatcher.drainQueue(since: Date().addingTimeInterval(-86_400))
        }
    }
    lastFocused = nowFocused
}
focusPollTimer.resume()
NSLog("[BriefingScheduler] focus poll timer started")

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: AssistantService
    init(service: AssistantService) { self.service = service }
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // Authenticate the peer: only the Assistant UI app may drive the
        // daemon's RPCs. Without this any same-user process could connect to
        // the Mach service and overwrite keys, spend LLM credits, or read the
        // conversation history.
        conn.setCodeSigningRequirement(
            XPCPeerRequirement.string(forIdentifier: "com.vishruth.assistant"))
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
