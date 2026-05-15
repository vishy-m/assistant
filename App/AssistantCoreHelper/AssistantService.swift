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

                var content: [LLMContentBlock] = []
                if let img = req.imageData, let mediaType = req.imageMediaType {
                    content.append(.image(LLMImage(mediaType: mediaType, data: img)))
                }
                content.append(.text(req.text))

                let initialMessages = [LLMMessage(role: .user, content: content)]
                let result = try await loop.run(initialMessages: initialMessages)
                response = PromptResponse(text: result.text,
                                          modelUsed: result.modelUsed,
                                          needsFollowup: false,
                                          errorMessage: nil)
            } catch {
                NSLog("[AssistantService] submitPrompt error: \(error)")
                response = PromptResponse(text: "", modelUsed: "",
                                          needsFollowup: false,
                                          errorMessage: "\(error)")
            }
            let data = (try? JSONEncoder().encode(response)) ?? Data()
            reply(data)
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
}
