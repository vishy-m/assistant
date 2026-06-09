import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM
import AssistantGCal
import AssistantGrades

final class AssistantService: NSObject, AssistantServiceProtocol {

    // Defense-in-depth bounds on submitPrompt, independent of XPC peer auth.
    private static let maxPromptTextBytes = 100_000        // 100 KB of prompt text
    private static let maxPromptImageBytes = 10 * 1024 * 1024  // 10 MB image payload

    private let db: AssistantDB
    private let taskRepo: TaskRepository
    private let gcalRepo: GCalRepository
    private var loop: ToolLoop
    private var gcalClient: GCalClient?
    private var calendarWriter: CalendarWriter?
    private var syncWorker: GCalSyncWorker?
    private let promptRateLimiter = RateLimiter(limit: 30, window: 60)

    init(db: AssistantDB, loop: ToolLoop) {
        self.db = db
        self.taskRepo = TaskRepository(db: db)
        self.gcalRepo = GCalRepository(db: db)
        self.loop = loop
    }

    func replaceLoop(_ newLoop: ToolLoop) {
        self.loop = newLoop
    }

    func attachGCalClient(_ client: GCalClient) {
        self.gcalClient = client
        self.calendarWriter = CalendarWriter(client: client, db: db)
    }

    func attachSyncWorker(_ worker: GCalSyncWorker) {
        self.syncWorker = worker
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

                // Bound payload size and request rate.
                if req.text.utf8.count > Self.maxPromptTextBytes
                    || (req.imageData?.count ?? 0) > Self.maxPromptImageBytes {
                    reply((try? JSONEncoder().encode(PromptResponse(
                        text: "", modelUsed: "", needsFollowup: false,
                        sessionId: nil, errorMessage: "Request too large."))) ?? Data())
                    return
                }
                if !promptRateLimiter.allow() {
                    reply((try? JSONEncoder().encode(PromptResponse(
                        text: "", modelUsed: "", needsFollowup: false,
                        sessionId: nil,
                        errorMessage: "Rate limit exceeded — try again in a moment."))) ?? Data())
                    return
                }

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

                // Build new user message. Prepend the current date/time so the
                // model can resolve relative phrases ("today", "tomorrow 5pm")
                // into the ISO-8601 timestamps the task/calendar tools need.
                var newUserContent: [LLMContentBlock] = []
                if let img = req.imageData, let mediaType = req.imageMediaType {
                    newUserContent.append(.image(LLMImage(mediaType: mediaType, data: img)))
                }
                let isoNow = ISO8601DateFormatter()
                isoNow.timeZone = .current
                let dateContext = "[Current date and time: \(isoNow.string(from: Date())) "
                    + "(\(TimeZone.current.identifier)). Resolve relative dates and times "
                    + "against this, and pass ISO-8601 timestamps with a timezone offset to "
                    + "any tool that accepts a date. Set a due date whenever the user implies one.]"
                newUserContent.append(.text(dateContext + "\n\n" + req.text))
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

    func googleAccountTimeZone(reply: @escaping (String?) -> Void) {
        guard let gcalClient else { reply(nil); return }
        _Concurrency.Task {
            reply(try? await gcalClient.accountTimeZone())
        }
    }

    func getDashboardSummary(reply: @escaping (Data) -> Void) {
        do {
            let courses = try CourseRepository(db: db).all()
            let gradeRepo = GradeRepository(db: db)
            let taskRepo = TaskRepository(db: db)

            var standings: [ClassStanding] = []
            var gpaInputs: [GPACalculator.CourseGrade] = []
            var allItems: [GradeItem] = []

            for course in courses {
                let cats = try gradeRepo.categories(forCourse: course.id)
                let items = try gradeRepo.items(forCourse: course.id)
                allItems.append(contentsOf: items)
                let input = try buildCalculatorInput(courseId: course.id, projection: [:])
                let breakdown = GradeCalculator.compute(input: input)
                let hasGradedWork = items.contains { $0.earnedPoints != nil }
                if !cats.isEmpty {
                    standings.append(ClassStanding(
                        courseId: course.id, courseName: course.name,
                        currentPct: breakdown.currentPct,
                        currentLetter: breakdown.currentLetter))
                }
                gpaInputs.append(GPACalculator.CourseGrade(
                    letter: breakdown.currentLetter,
                    creditHours: course.creditHours,
                    hasGradedWork: hasGradedWork))
            }

            let gpa = GPACalculator.compute(gpaInputs)
            let courseName: [String: String] = Dictionary(
                uniqueKeysWithValues: courses.map { ($0.id, $0.name) })

            let recent = allItems
                .filter { $0.earnedPoints != nil }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(5)
                .map { item in
                    RecentGrade(
                        itemId: item.id,
                        courseName: courseName[item.courseId] ?? "—",
                        itemName: item.name,
                        earnedPct: item.maxPoints > 0
                            ? ((item.earnedPoints ?? 0) / item.maxPoints) * 100 : 0,
                        enteredAt: item.updatedAt)
                }

            let tasks = try taskRepo.all()
            let entries = DueSoonAggregator.aggregate(
                tasks: tasks, gradeItems: allItems, now: Date())
            let dueSoon = entries.map { e in
                DueSoonItem(id: e.id,
                            kind: e.kind == .task ? .task : .gradeItem,
                            title: e.title,
                            courseName: e.courseId.flatMap { courseName[$0] },
                            category: e.category,
                            dueAt: e.dueAt, isOverdue: e.isOverdue)
            }

            let summary = DashboardSummary(
                gpa: gpa.gpa, gpaCountedCourses: gpa.countedCourses,
                gpaTotalCourses: gpa.totalCourses,
                classes: standings, recentGrades: Array(recent), dueSoon: dueSoon)
            reply(try JSONEncoder().encode(summary))
        } catch {
            NSLog("[AssistantService] getDashboardSummary error: \(error)")
            reply(Data())
        }
    }

    func getWeekEvents(startISO: String, endISO: String, reply: @escaping (Data) -> Void) {
        let iso = ISO8601DateFormatter()
        guard let start = iso.date(from: startISO), let end = iso.date(from: endISO) else {
            reply(Data()); return
        }
        do {
            let cal = Calendar(identifier: .gregorian)
            var events: [WeekEvent] = []
            var seen = Set<String>()
            var day = cal.startOfDay(for: start)
            let repo = GCalRepository(db: db)
            while day < end {
                for e in try repo.eventsOn(date: day) where !seen.contains(e.gcalEventId) {
                    seen.insert(e.gcalEventId)
                    events.append(WeekEvent(
                        id: e.gcalEventId, title: e.title,
                        startAt: e.startAt, endAt: e.endAt,
                        category: e.category, location: e.location,
                        isRecurring: e.recurringEventId != nil,
                        courseId: e.courseId, eventType: e.eventType))
                }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? end
            }
            reply(try JSONEncoder().encode(WeekEventsResponse(events: events)))
        } catch {
            NSLog("[AssistantService] getWeekEvents error: \(error)")
            reply(Data())
        }
    }

    func createCalendarEvent(_ data: Data, reply: @escaping (Data) -> Void) {
        guard let writer = calendarWriter,
              let req = try? JSONDecoder().decode(CreateEventRequest.self, from: data) else {
            reply((try? JSONEncoder().encode(CalendarWriteResult(
                event: nil, errorMessage: "bad request"))) ?? Data())
            return
        }
        _Concurrency.Task {
            do {
                let ev = try await writer.create(
                    title: req.title, start: req.startAt, end: req.endAt,
                    location: req.location, description: nil, category: req.category,
                    recurrence: req.recurrence,
                    courseId: req.courseId, eventType: req.eventType)
                // A recurring master is not cached locally; pull its expanded
                // occurrences in now so the calendar shows them immediately.
                if req.recurrence != nil {
                    do {
                        try await syncWorker?.runOnce()
                    } catch {
                        NSLog("[AssistantService] post-create sync error: \(error)")
                    }
                }
                reply((try? JSONEncoder().encode(CalendarWriteResult(
                    event: ev, errorMessage: nil))) ?? Data())
            } catch {
                reply((try? JSONEncoder().encode(CalendarWriteResult(
                    event: nil, errorMessage: "\(error)"))) ?? Data())
            }
        }
    }

    func updateCalendarEvent(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let writer = calendarWriter,
              let req = try? JSONDecoder().decode(UpdateEventRequest.self, from: data) else {
            reply(false); return
        }
        _Concurrency.Task {
            do {
                try await writer.update(eventId: req.eventId,
                                        start: req.startAt, end: req.endAt)
                reply(true)
            } catch {
                NSLog("[AssistantService] updateCalendarEvent error: \(error)")
                reply(false)
            }
        }
    }

    func deleteCalendarEvent(eventId: String, reply: @escaping (Bool) -> Void) {
        guard let writer = calendarWriter else { reply(false); return }
        _Concurrency.Task {
            do {
                try await writer.delete(eventId: eventId)
                reply(true)
            } catch {
                NSLog("[AssistantService] deleteCalendarEvent error: \(error)")
                reply(false)
            }
        }
    }

    func listCategories(reply: @escaping (Data) -> Void) {
        do {
            let categories = try CategoryRepository(db: db).all()
            reply(try JSONEncoder().encode(categories))
        } catch {
            NSLog("[AssistantService] listCategories error: \(error)")
            reply(Data())
        }
    }

    func listEventTypes(reply: @escaping (Data) -> Void) {
        do {
            let types = try EventTypeRepository(db: db).all()
            let dtos = types.map {
                EventTypeDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex,
                             symbolName: $0.symbolName, isBuiltin: $0.isBuiltin)
            }
            reply(try JSONEncoder().encode(dtos))
        } catch {
            NSLog("[AssistantService] listEventTypes error: \(error)")
            reply(Data())
        }
    }

    func upsertEventType(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let dto = try? JSONDecoder().decode(EventTypeDTO.self, from: data) else {
            reply(false); return
        }
        do {
            let repo = EventTypeRepository(db: db)
            let existing = try repo.find(id: dto.id)
            let sortOrder: Int
            if let existing {
                sortOrder = existing.sortOrder
            } else {
                sortOrder = (try repo.all().map(\.sortOrder).max() ?? 0) + 1
            }
            try repo.upsert(EventType(
                id: dto.id, name: dto.name, colorHex: dto.colorHex,
                googleColorId: GoogleEventColor.nearestColorId(toHex: dto.colorHex),
                symbolName: dto.symbolName,
                isBuiltin: existing?.isBuiltin ?? false, sortOrder: sortOrder))
            reply(true)
        } catch {
            NSLog("[AssistantService] upsertEventType error: \(error)")
            reply(false)
        }
    }

    func deleteEventType(id: String, reply: @escaping (Bool) -> Void) {
        do {
            try EventTypeRepository(db: db).delete(id: id)  // no-ops on built-ins
            reply(true)
        } catch {
            NSLog("[AssistantService] deleteEventType error: \(error)")
            reply(false)
        }
    }

    func listClasses(reply: @escaping (Data) -> Void) {
        do {
            let courses = try CourseRepository(db: db).all()
            let allTasks = try TaskRepository(db: db).all()
            let gcalRepo = GCalRepository(db: db)
            let summaries = try courses.map { course -> ClassSummary in
                let events = try gcalRepo.eventsForCourse(course.id)
                let tasks = allTasks.filter { $0.courseId == course.id }
                return ClassDetailAssembler.summary(course: course, events: events, tasks: tasks)
            }
            reply(try JSONEncoder().encode(summaries))
        } catch {
            NSLog("[AssistantService] listClasses error: \(error)")
            reply(Data())
        }
    }

    func getClassDetail(courseId: String, reply: @escaping (Data) -> Void) {
        do {
            guard let course = try CourseRepository(db: db).find(id: courseId) else {
                reply(Data()); return
            }
            let events = try GCalRepository(db: db).eventsForCourse(courseId)
            let tasks = try TaskRepository(db: db).all().filter { $0.courseId == courseId }
            let detail = ClassDetailAssembler.detail(course: course, events: events, tasks: tasks)
            reply(try JSONEncoder().encode(detail))
        } catch {
            NSLog("[AssistantService] getClassDetail error: \(error)")
            reply(Data())
        }
    }

    private func classFileStorage() -> ClassFileStorage? {
        (try? ClassFileStorage.defaultBase()).map { ClassFileStorage(base: $0) }
    }

    func listClassFolders(courseId: String, reply: @escaping (Data) -> Void) {
        do {
            let dtos = try ClassFolderRepository(db: db).all(courseId: courseId).map {
                ClassFolderDTO(id: $0.id, courseId: $0.courseId,
                               parentFolderId: $0.parentFolderId, name: $0.name,
                               sortOrder: $0.sortOrder)
            }
            reply(try JSONEncoder().encode(dtos))
        } catch { NSLog("[AssistantService] listClassFolders error: \(error)"); reply(Data()) }
    }

    func listClassFiles(courseId: String, reply: @escaping (Data) -> Void) {
        do {
            let dtos = try ClassFileRepository(db: db).all(courseId: courseId).map {
                ClassFileDTO(id: $0.id, courseId: $0.courseId, folderId: $0.folderId,
                             name: $0.name, storedName: $0.storedName,
                             contentType: $0.contentType, byteSize: $0.byteSize)
            }
            reply(try JSONEncoder().encode(dtos))
        } catch { NSLog("[AssistantService] listClassFiles error: \(error)"); reply(Data()) }
    }

    func createClassFolder(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let dto = try? JSONDecoder().decode(ClassFolderDTO.self, from: data) else {
            reply(false); return
        }
        do {
            try ClassFolderRepository(db: db).create(ClassFolder(
                id: dto.id, courseId: dto.courseId, parentFolderId: dto.parentFolderId,
                name: dto.name, sortOrder: dto.sortOrder))
            reply(true)
        } catch { NSLog("[AssistantService] createClassFolder error: \(error)"); reply(false) }
    }

    func renameClassFolder(id: String, name: String, reply: @escaping (Bool) -> Void) {
        do { try ClassFolderRepository(db: db).rename(id: id, name: name); reply(true) }
        catch { NSLog("[AssistantService] renameClassFolder error: \(error)"); reply(false) }
    }

    func moveClassFolder(id: String, parentId: String?, reply: @escaping (Bool) -> Void) {
        do { try ClassFolderRepository(db: db).move(id: id, toParent: parentId); reply(true) }
        catch { NSLog("[AssistantService] moveClassFolder error: \(error)"); reply(false) }
    }

    func deleteClassFolder(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let courseId = try ClassFolderRepository(db: db).find(id: id)?.courseId
            let storedNames = try ClassFolderRepository(db: db).deleteRecursively(id: id)
            if let courseId, let storage = classFileStorage() {
                for name in storedNames {
                    try? storage.remove(courseId: courseId, storedName: name)
                }
            }
            reply(true)
        } catch { NSLog("[AssistantService] deleteClassFolder error: \(error)"); reply(false) }
    }

    func addClassFile(_ data: Data, bytes: Data, reply: @escaping (Bool) -> Void) {
        guard let dto = try? JSONDecoder().decode(ClassFileDTO.self, from: data),
              let storage = classFileStorage() else { reply(false); return }
        do {
            try storage.write(bytes, courseId: dto.courseId, storedName: dto.storedName)
            try ClassFileRepository(db: db).create(ClassFile(
                id: dto.id, courseId: dto.courseId, folderId: dto.folderId, name: dto.name,
                storedName: dto.storedName, contentType: dto.contentType, byteSize: dto.byteSize))
            reply(true)
        } catch { NSLog("[AssistantService] addClassFile error: \(error)"); reply(false) }
    }

    func renameClassFile(id: String, name: String, reply: @escaping (Bool) -> Void) {
        do { try ClassFileRepository(db: db).rename(id: id, name: name); reply(true) }
        catch { NSLog("[AssistantService] renameClassFile error: \(error)"); reply(false) }
    }

    func moveClassFile(id: String, folderId: String?, reply: @escaping (Bool) -> Void) {
        do { try ClassFileRepository(db: db).move(id: id, toFolder: folderId); reply(true) }
        catch { NSLog("[AssistantService] moveClassFile error: \(error)"); reply(false) }
    }

    func deleteClassFile(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let courseId = try ClassFileRepository(db: db).find(id: id)?.courseId
            let stored = try ClassFileRepository(db: db).delete(id: id)
            if let courseId, let stored, let storage = classFileStorage() {
                try? storage.remove(courseId: courseId, storedName: stored)
            }
            reply(true)
        } catch { NSLog("[AssistantService] deleteClassFile error: \(error)"); reply(false) }
    }

    func saveCategory(originalName: String?, name: String, colorHex: String,
                      reply: @escaping (Bool) -> Void) {
        let repo = CategoryRepository(db: db)
        do {
            if let originalName {
                let existing = try repo.find(name: originalName)
                let updated = Category(name: name, colorHex: colorHex,
                                       isDefault: existing?.isDefault ?? false)
                try repo.update(originalName: originalName, to: updated)
                reply(true)
                if existing?.colorHex != colorHex {
                    recolorGoogleEvents(category: name, colorHex: colorHex)
                }
            } else {
                try repo.create(Category(name: name, colorHex: colorHex))
                reply(true)
            }
        } catch {
            NSLog("[AssistantService] saveCategory error: \(error)")
            reply(false)
        }
    }

    func removeCategory(name: String, reply: @escaping (Bool) -> Void) {
        do {
            try CategoryRepository(db: db).delete(name: name)
            reply(true)
        } catch {
            NSLog("[AssistantService] removeCategory error: \(error)")
            reply(false)
        }
    }

    func setEventCategory(eventId: String, category: String,
                          reply: @escaping (Bool) -> Void) {
        let gcalRepo = GCalRepository(db: db)
        let catRepo = CategoryRepository(db: db)
        do {
            guard var cached = try gcalRepo.find(id: eventId) else { reply(false); return }
            let resolved = try catRepo.resolve(category)
            cached.category = resolved.name
            try gcalRepo.upsert(cached)
            reply(true)
            if let client = gcalClient {
                let colorId = GoogleEventColor.nearestColorId(toHex: resolved.colorHex)
                _Concurrency.Task {
                    _ = try? await client.updateEvent(
                        calendarId: cached.calendarId, eventId: eventId,
                        summary: nil, start: nil, end: nil,
                        location: nil, description: nil, colorId: colorId)
                }
            }
        } catch {
            NSLog("[AssistantService] setEventCategory error: \(error)")
            reply(false)
        }
    }

    func setEventClassification(eventId: String, courseId: String?, eventType: String?,
                                reply: @escaping (Bool) -> Void) {
        guard let writer = calendarWriter else { reply(false); return }
        _Concurrency.Task {
            do {
                try await writer.updateClassification(eventId: eventId,
                                                      courseId: courseId, eventType: eventType)
                reply(true)
            } catch {
                NSLog("[AssistantService] setEventClassification error: \(error)")
                reply(false)
            }
        }
    }

    func getWeekTasks(startISO: String, endISO: String, reply: @escaping (Data) -> Void) {
        let iso = ISO8601DateFormatter()
        guard let start = iso.date(from: startISO), let end = iso.date(from: endISO) else {
            reply(Data()); return
        }
        do {
            let tasks = try taskRepo.dueInRange(start: start, end: end)
            let weekTasks = tasks.map { t in
                WeekTask(id: t.id, title: t.title,
                         dueAt: t.dueAt ?? Date(), category: t.category)
            }
            reply(try JSONEncoder().encode(WeekTasksResponse(tasks: weekTasks)))
        } catch {
            NSLog("[AssistantService] getWeekTasks error: \(error)")
            reply(Data())
        }
    }

    func rescheduleTask(taskId: String, dueISO: String, reply: @escaping (Bool) -> Void) {
        let iso = ISO8601DateFormatter()
        guard let due = iso.date(from: dueISO) else { reply(false); return }
        do {
            try taskRepo.setDueAt(id: taskId, dueAt: due)
            reply(true)
        } catch {
            NSLog("[AssistantService] rescheduleTask error: \(error)")
            reply(false)
        }
    }

    func completeTask(taskId: String, reply: @escaping (Bool) -> Void) {
        do {
            try taskRepo.complete(id: taskId)
            reply(true)
        } catch {
            NSLog("[AssistantService] completeTask error: \(error)")
            reply(false)
        }
    }

    func listTasks(reply: @escaping (Data) -> Void) {
        do {
            reply(try JSONEncoder().encode(try taskRepo.all()))
        } catch {
            NSLog("[AssistantService] listTasks error: \(error)")
            reply(Data())
        }
    }

    func createTask(_ data: Data, reply: @escaping (Bool) -> Void) {
        do {
            let task = try JSONDecoder().decode(AssistantStore.Task.self, from: data)
            try taskRepo.insert(task)
            reply(true)
        } catch {
            NSLog("[AssistantService] createTask error: \(error)")
            reply(false)
        }
    }

    func updateTask(_ data: Data, reply: @escaping (Bool) -> Void) {
        do {
            let task = try JSONDecoder().decode(AssistantStore.Task.self, from: data)
            try taskRepo.update(task)
            reply(true)
        } catch {
            NSLog("[AssistantService] updateTask error: \(error)")
            reply(false)
        }
    }

    func deleteTask(taskId: String, reply: @escaping (Bool) -> Void) {
        do {
            try taskRepo.delete(id: taskId)
            reply(true)
        } catch {
            NSLog("[AssistantService] deleteTask error: \(error)")
            reply(false)
        }
    }

    func setTaskCompleted(taskId: String, completed: Bool, reply: @escaping (Bool) -> Void) {
        do {
            try taskRepo.setCompleted(id: taskId, completed: completed)
            reply(true)
        } catch {
            NSLog("[AssistantService] setTaskCompleted error: \(error)")
            reply(false)
        }
    }

    func clearCompletedTasks(reply: @escaping (Bool) -> Void) {
        do {
            try taskRepo.deleteCompleted()
            reply(true)
        } catch {
            NSLog("[AssistantService] clearCompletedTasks error: \(error)")
            reply(false)
        }
    }

    func getTasksNote(reply: @escaping (String) -> Void) {
        reply(((try? SettingRepository(db: db).get("tasks_scratchpad")) ?? nil) ?? "")
    }

    func setTasksNote(_ note: String, reply: @escaping (Bool) -> Void) {
        do {
            try SettingRepository(db: db).set("tasks_scratchpad", value: note)
            reply(true)
        } catch {
            NSLog("[AssistantService] setTasksNote error: \(error)")
            reply(false)
        }
    }

    /// Re-PATCHes the Google colorId of every cached event in a category.
    private func recolorGoogleEvents(category: String, colorHex: String) {
        guard let client = gcalClient else { return }
        let colorId = GoogleEventColor.nearestColorId(toHex: colorHex)
        _Concurrency.Task {
            let events = (try? CategoryRepository(db: self.db).events(category: category)) ?? []
            let quota = QuotaGuard(db: self.db)
            for ev in events {
                guard (try? quota.tryConsume()) == true else { break }
                _ = try? await client.updateEvent(
                    calendarId: ev.calendarId, eventId: ev.gcalEventId,
                    summary: nil, start: nil, end: nil,
                    location: nil, description: nil, colorId: colorId)
            }
        }
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
