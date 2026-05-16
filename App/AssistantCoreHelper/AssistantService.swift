import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM
import AssistantGCal
import AssistantGrades

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

    func computeGrade(courseId: String, projectionJSON: Data?, reply: @escaping (Data) -> Void) {
        do {
            let projection: [String: Double]
            if let pjData = projectionJSON,
               let decoded = try? JSONDecoder().decode([String: Double].self, from: pjData) {
                projection = decoded
            } else {
                projection = [:]
            }
            let input = try buildCalculatorInput(courseId: courseId, projection: projection)
            let breakdown = GradeCalculator.compute(input: input)
            let data = try JSONEncoder().encode(breakdown)
            reply(data)
        } catch {
            NSLog("[AssistantService] computeGrade error: \(error)")
            reply(Data())
        }
    }

    func enterGrade(itemId: String, earnedPoints: Double, reply: @escaping (Bool) -> Void) {
        do {
            try GradeRepository(db: db).setEarnedPoints(itemId: itemId, earned: earnedPoints)
            reply(true)
        } catch {
            NSLog("[AssistantService] enterGrade error: \(error)")
            reply(false)
        }
    }

    func listCourses(reply: @escaping (Data) -> Void) {
        do {
            let courses = try CourseRepository(db: db).all()
            reply(try JSONEncoder().encode(courses))
        } catch {
            NSLog("[AssistantService] listCourses error: \(error)")
            reply(Data())
        }
    }

    func upsertCourse(_ data: Data, reply: @escaping (Bool) -> Void) {
        do {
            let course = try JSONDecoder().decode(Course.self, from: data)
            let repo = CourseRepository(db: db)
            if try repo.find(id: course.id) != nil {
                try repo.update(course)
            } else {
                try repo.insert(course)
            }
            reply(true)
        } catch {
            NSLog("[AssistantService] upsertCourse error: \(error)")
            reply(false)
        }
    }

    func listGradeData(courseId: String, reply: @escaping (Data) -> Void) {
        do {
            let repo = GradeRepository(db: db)
            let cats = try repo.categories(forCourse: courseId)
            let items = try repo.items(forCourse: courseId)
            let dto = GradeDataDTO(
                categoriesJSON: try JSONEncoder().encode(cats),
                itemsJSON: try JSONEncoder().encode(items))
            reply(try JSONEncoder().encode(dto))
        } catch {
            NSLog("[AssistantService] listGradeData error: \(error)")
            reply(Data())
        }
    }

    func upsertCategory(_ data: Data, reply: @escaping (Bool) -> Void) {
        do {
            let cat = try JSONDecoder().decode(GradeCategory.self, from: data)
            let repo = GradeRepository(db: db)
            let existing = try repo.categories(forCourse: cat.courseId)
            if existing.contains(where: { $0.id == cat.id }) {
                try repo.updateCategory(cat)
            } else {
                try repo.insertCategory(cat)
            }
            reply(true)
        } catch {
            NSLog("[AssistantService] upsertCategory error: \(error)")
            reply(false)
        }
    }

    func upsertItem(_ data: Data, reply: @escaping (Bool) -> Void) {
        do {
            let item = try JSONDecoder().decode(GradeItem.self, from: data)
            let repo = GradeRepository(db: db)
            if try repo.findItem(id: item.id) != nil {
                try repo.updateItem(item)
            } else {
                try repo.insertItem(item)
            }
            reply(true)
        } catch {
            NSLog("[AssistantService] upsertItem error: \(error)")
            reply(false)
        }
    }

    func deleteCategory(id: String, reply: @escaping (Bool) -> Void) {
        do {
            try GradeRepository(db: db).deleteCategory(id: id)
            reply(true)
        } catch {
            NSLog("[AssistantService] deleteCategory error: \(error)")
            reply(false)
        }
    }

    func deleteItem(id: String, reply: @escaping (Bool) -> Void) {
        do {
            try GradeRepository(db: db).deleteItem(id: id)
            reply(true)
        } catch {
            NSLog("[AssistantService] deleteItem error: \(error)")
            reply(false)
        }
    }

    func deleteCourse(id: String, reply: @escaping (Bool) -> Void) {
        do {
            try CourseRepository(db: db).delete(id: id)
            reply(true)
        } catch {
            NSLog("[AssistantService] deleteCourse error: \(error)")
            reply(false)
        }
    }

    func setProviderAPIKey(provider: String, key: String, reply: @escaping (Bool) -> Void) {
        do {
            let account: KeychainAccount
            switch provider {
            case "claude": account = .claudeAPIKey
            case "openai": account = .openaiAPIKey
            case "gemma_hosted": account = .gemmaHostedAPIKey
            default: reply(false); return
            }
            if key.isEmpty {
                try KeychainStore().delete(account: account.rawValue)
            } else {
                try KeychainStore().set(account, value: key)
            }
            reply(true)
        } catch {
            NSLog("[AssistantService] setProviderAPIKey error: \(error)")
            reply(false)
        }
    }

    func getProviderConfigured(provider: String, reply: @escaping (Bool) -> Void) {
        let account: KeychainAccount
        switch provider {
        case "claude": account = .claudeAPIKey
        case "openai": account = .openaiAPIKey
        case "gemma_hosted": account = .gemmaHostedAPIKey
        default: reply(false); return
        }
        let configured = ((try? KeychainStore().get(account)) ?? nil) != nil
        reply(configured)
    }

    func getSettings(reply: @escaping (Data) -> Void) {
        let repo = SettingRepository(db: db)
        let s: AppSettings = (try? repo.getCodable("app_settings")) ?? .default
        let data = (try? JSONEncoder().encode(s)) ?? Data()
        reply(data)
    }

    func setSettings(_ data: Data, reply: @escaping (Bool) -> Void) {
        do {
            let s = try JSONDecoder().decode(AppSettings.self, from: data)
            try SettingRepository(db: db).setCodable("app_settings", value: s)
            // Mirror the per-key settings the scheduler reads
            struct HM: Codable { let hour: Int; let minute: Int }
            try SettingRepository(db: db).setCodable("morning_briefing_time",
                value: HM(hour: s.morningBriefingHour, minute: s.morningBriefingMinute))
            try SettingRepository(db: db).setCodable("evening_briefing_time",
                value: HM(hour: s.eveningBriefingHour, minute: s.eveningBriefingMinute))
            reply(true)
        } catch {
            NSLog("[AssistantService] setSettings error: \(error)")
            reply(false)
        }
    }

    func clearGoogleRefreshToken(reply: @escaping (Bool) -> Void) {
        do {
            try GCalAuthStore().clear()
            reply(true)
        } catch {
            reply(false)
        }
    }

    func setGoogleClientSecret(_ secret: String, reply: @escaping (Bool) -> Void) {
        do {
            if secret.isEmpty {
                try KeychainStore().delete(account: KeychainAccount.googleOAuthClientSecret.rawValue)
            } else {
                try KeychainStore().set(.googleOAuthClientSecret, value: secret)
            }
            reply(true)
        } catch {
            NSLog("[AssistantService] setGoogleClientSecret error: \(error)")
            reply(false)
        }
    }

    func getGoogleClientSecret(reply: @escaping (String?) -> Void) {
        reply((try? KeychainStore().get(.googleOAuthClientSecret)) ?? nil)
    }

    private func buildCalculatorInput(courseId: String,
                                       projection: [String: Double]) throws -> GradeCalculatorInput {
        let gradeRepo = GradeRepository(db: db)
        let cats = try gradeRepo.categories(forCourse: courseId).map {
            GradeCalculatorInput.CategoryIn(
                id: $0.id, name: $0.name, weightPct: $0.weightPct,
                dropLowestN: $0.dropLowestN, dropHighestN: $0.dropHighestN)
        }
        let items = try gradeRepo.items(forCourse: courseId).map {
            GradeCalculatorInput.ItemIn(
                id: $0.id, categoryId: $0.categoryId,
                maxPoints: $0.maxPoints, earnedPoints: $0.earnedPoints,
                isExtraCredit: $0.isExtraCredit,
                weightOverridePct: $0.weightOverridePct)
        }
        return GradeCalculatorInput(categories: cats, items: items, projection: projection)
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
