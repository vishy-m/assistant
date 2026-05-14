import Foundation
import AssistantShared
import AssistantStore

final class AssistantService: NSObject, AssistantServiceProtocol {

    private let db: AssistantDB
    private let taskRepo: TaskRepository
    private let gcalRepo: GCalRepository

    init(db: AssistantDB) {
        self.db = db
        self.taskRepo = TaskRepository(db: db)
        self.gcalRepo = GCalRepository(db: db)
    }

    func ping(reply: @escaping (String) -> Void) {
        reply("pong")
    }

    func getTodayPlan(reply: @escaping (Data) -> Void) {
        do {
            let today = Date()
            let tasks = try taskRepo.dueOn(date: today)
            let events = try gcalRepo.eventsOn(date: today)

            var items: [TodayPlan.Item] = []
            items.append(contentsOf: tasks.map { t in
                TodayPlan.Item(kind: .task, id: t.id, title: t.title,
                               startAt: nil, dueAt: t.dueAt,
                               location: nil, category: t.category)
            })
            items.append(contentsOf: events.map { e in
                TodayPlan.Item(kind: .event, id: e.gcalEventId, title: e.title,
                               startAt: e.startAt, dueAt: nil,
                               location: e.location, category: e.category)
            })
            items.sort { (lhs, rhs) -> Bool in
                let l = lhs.startAt ?? lhs.dueAt ?? .distantFuture
                let r = rhs.startAt ?? rhs.dueAt ?? .distantFuture
                return l < r
            }

            let plan = TodayPlan(items: items)
            let data = try JSONEncoder().encode(plan)
            reply(data)
        } catch {
            NSLog("[AssistantService] getTodayPlan error: \(error)")
            reply(Data())  // empty data signals error to client
        }
    }
}
