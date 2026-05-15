import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM
import AssistantGCal

final class AssistantService: NSObject, AssistantServiceProtocol {

    private let db: AssistantDB
    private let taskRepo: TaskRepository
    private let gcalRepo: GCalRepository
    private var loop: ToolLoop

    init(db: AssistantDB, loop: ToolLoop) {
        self.db = db
        self.taskRepo = TaskRepository(db: db)
        self.gcalRepo = GCalRepository(db: db)
        self.loop = loop
    }

    func replaceLoop(_ newLoop: ToolLoop) {
        self.loop = newLoop
    }

    func ping(reply: @escaping (String) -> Void) { reply("pong") }

    func getTodayPlan(reply: @escaping (Data) -> Void) {
        do {
            let today = Date()
            let tasks = try taskRepo.dueOn(date: today)
            let events = try gcalRepo.eventsOn(date: today)
            var items: [TodayPlan.Item] = []
            items.append(contentsOf: tasks.map {
                TodayPlan.Item(kind: .task, id: $0.id, title: $0.title,
                               startAt: nil, dueAt: $0.dueAt,
                               location: nil, category: $0.category)
            })
            items.append(contentsOf: events.map {
                TodayPlan.Item(kind: .event, id: $0.gcalEventId, title: $0.title,
                               startAt: $0.startAt, dueAt: nil,
                               location: $0.location, category: $0.category)
            })
            items.sort { (l, r) in (l.startAt ?? l.dueAt ?? .distantFuture) < (r.startAt ?? r.dueAt ?? .distantFuture) }
            let data = try JSONEncoder().encode(TodayPlan(items: items))
            reply(data)
        } catch {
            NSLog("[AssistantService] getTodayPlan error: \(error)")
            reply(Data())
        }
    }

    func submitPrompt(_ requestData: Data, reply: @escaping (Data) -> Void) {
        _Concurrency.Task {
            let response: PromptResponse
            do {
                let req = try JSONDecoder().decode(PromptRequest.self, from: requestData)
                let convoRepo = ConversationRepository(db: db)

                // Resolve or create the conversation
                let sessionId: String
                var historyMessages: [LLMMessage] = []
                if let existing = req.sessionId, (try convoRepo.find(id: existing)) != nil {
                    sessionId = existing
                    let priorMsgs = try convoRepo.messages(in: existing)
                    historyMessages = priorMsgs.map { m in
                        let role: LLMRole = (m.role == "assistant") ? .assistant : .user
                        return LLMMessage(role: role, content: [.text(m.content)])
                    }
                } else {
                    let newConvo = try convoRepo.start(id: UUID().uuidString)
                    sessionId = newConvo.id
                }

                // Build new user message
                var newUserContent: [LLMContentBlock] = []
                if let img = req.imageData, let mediaType = req.imageMediaType {
                    newUserContent.append(.image(LLMImage(mediaType: mediaType, data: img)))
                }
                newUserContent.append(.text(req.text))
                let newUserMessage = LLMMessage(role: .user, content: newUserContent)

                // Persist user message immediately (so it's recorded even if LLM fails)
                let userMsgId = UUID().uuidString
                try convoRepo.appendMessage(Message(
                    id: userMsgId, conversationId: sessionId,
                    role: "user", content: req.text,
                    attachedImagePath: nil,
                    toolCallsJson: nil, modelUsed: nil, createdAt: Date()))

                let allMessages = historyMessages + [newUserMessage]
                let result = try await loop.run(initialMessages: allMessages)

                // Persist assistant reply
                let asstMsgId = UUID().uuidString
                try convoRepo.appendMessage(Message(
                    id: asstMsgId, conversationId: sessionId,
                    role: "assistant", content: result.text,
                    attachedImagePath: nil,
                    toolCallsJson: nil, modelUsed: result.modelUsed, createdAt: Date()))

                response = PromptResponse(
                    text: result.text, modelUsed: result.modelUsed,
                    needsFollowup: false, sessionId: sessionId, errorMessage: nil)
            } catch {
                NSLog("[AssistantService] submitPrompt error: \(error)")
                response = PromptResponse(text: "", modelUsed: "",
                                          needsFollowup: false, sessionId: nil,
                                          errorMessage: "\(error)")
            }
            let data = (try? JSONEncoder().encode(response)) ?? Data()
            reply(data)
        }
    }

    func getMostRecentSessionId(reply: @escaping (String?) -> Void) {
        do {
            let convo = try ConversationRepository(db: db).mostRecent(limit: 1).first
            reply(convo?.id)
        } catch {
            reply(nil)
        }
    }

    func getMessages(sessionId: String, reply: @escaping (Data) -> Void) {
        do {
            let msgs = try ConversationRepository(db: db).messages(in: sessionId)
            let dtos = msgs.map { MessageDTO(id: $0.id, role: $0.role, content: $0.content,
                                              modelUsed: $0.modelUsed, createdAt: $0.createdAt) }
            let data = try JSONEncoder().encode(dtos)
            reply(data)
        } catch {
            reply(Data())
        }
    }

    func setGoogleRefreshToken(_ token: String, reply: @escaping (Bool) -> Void) {
        do {
            try GCalAuthStore().setRefreshToken(token)
            reply(true)
        } catch {
            NSLog("[AssistantService] setGoogleRefreshToken error: \(error)")
            reply(false)
        }
    }

    private var eventClientConnection: NSXPCConnection?

    func registerEventClient(_ endpoint: NSXPCListenerEndpoint, reply: @escaping (Bool) -> Void) {
        let conn = NSXPCConnection(listenerEndpoint: endpoint)
        conn.remoteObjectInterface = NSXPCInterface(with: AssistantEventsProtocol.self)
        conn.invalidationHandler = { [weak self] in
            NSLog("[AssistantService] event client invalidated")
            self?.eventClientConnection = nil
        }
        conn.resume()
        self.eventClientConnection = conn
        reply(true)
    }

    func pushBriefing(_ payload: BriefingPayload) -> Bool {
        guard let conn = eventClientConnection else { return false }
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            NSLog("[AssistantService] briefing push error: \(err)")
        }) as? AssistantEventsProtocol else {
            return false
        }
        do {
            let data = try JSONEncoder().encode(payload)
            proxy.briefingReady(data) { _ in }
            return true
        } catch {
            return false
        }
    }
}
