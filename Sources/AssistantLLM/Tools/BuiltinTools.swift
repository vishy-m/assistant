import Foundation
import AssistantStore

public enum BuiltinTools {

    public static func registerTaskTools(into registry: inout ToolRegistry,
                                          taskRepo: TaskRepository,
                                          gcalRepo: GCalRepository,
                                          clock: @escaping @Sendable () -> Date = { Date() }) {

        // create_task
        registry.register(
            tool: LLMTool(
                name: "create_task",
                description: "Create a new task / to-do with an optional due date.",
                inputSchema: #"""
                {
                  "type": "object",
                  "properties": {
                    "title":     { "type": "string" },
                    "notes":     { "type": "string" },
                    "due_at":    { "type": "string", "description": "ISO 8601 datetime" },
                    "course_id": { "type": "string" },
                    "category":  { "type": "string", "default": "generic" }
                  },
                  "required": ["title"]
                }
                """#),
            handler: { argsJSON in
                struct Args: Decodable {
                    let title: String
                    let notes: String?
                    let due_at: String?
                    let course_id: String?
                    let category: String?
                }
                let args = try JSONDecoder().decode(Args.self, from: argsJSON.data(using: .utf8) ?? Data())
                let dueAt = args.due_at.flatMap { ISO8601DateFormatter().date(from: $0) }
                let id = UUID().uuidString
                let t = AssistantStore.Task(
                    id: id, title: args.title, notes: args.notes,
                    dueAt: dueAt, completedAt: nil,
                    courseId: args.course_id, gradeItemId: nil,
                    priority: 0,
                    category: args.category ?? "generic",
                    source: "agent")
                try taskRepo.insert(t)
                return #"{"id":"\#(id)","status":"created"}"#
            })

        // complete_task
        registry.register(
            tool: LLMTool(
                name: "complete_task",
                description: "Mark a task as completed by id.",
                inputSchema: #"{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}"#),
            handler: { argsJSON in
                struct Args: Decodable { let id: String }
                let args = try JSONDecoder().decode(Args.self, from: argsJSON.data(using: .utf8) ?? Data())
                try taskRepo.complete(id: args.id)
                return #"{"status":"completed"}"#
            })

        // list_tasks
        registry.register(
            tool: LLMTool(
                name: "list_tasks",
                description: "List tasks. filter ∈ today, this_week, overdue, all",
                inputSchema: #"{"type":"object","properties":{"filter":{"type":"string"}}}"#),
            handler: { argsJSON in
                struct Args: Decodable { let filter: String? }
                let args = (try? JSONDecoder().decode(Args.self,
                                                     from: argsJSON.data(using: .utf8) ?? Data()))
                let filter = args?.filter ?? "today"
                let now = clock()
                let tasks: [AssistantStore.Task]
                switch filter {
                case "overdue":
                    tasks = try taskRepo.overdue(asOf: now)
                case "today":
                    tasks = try taskRepo.dueOn(date: now)
                default:
                    tasks = try taskRepo.dueOn(date: now)
                }
                struct Out: Encodable { let tasks: [TaskOut] }
                struct TaskOut: Encodable {
                    let id: String; let title: String; let due_at: String?
                    let category: String
                }
                let outs = tasks.map {
                    TaskOut(id: $0.id, title: $0.title,
                            due_at: $0.dueAt.map(ISO8601DateFormatter().string(from:)),
                            category: $0.category)
                }
                let data = try JSONEncoder().encode(Out(tasks: outs))
                return String(data: data, encoding: .utf8) ?? "{}"
            })

        // get_today_plan
        registry.register(
            tool: LLMTool(
                name: "get_today_plan",
                description: "Return UNION of today's tasks and calendar events.",
                inputSchema: #"{"type":"object"}"#),
            handler: { _ in
                let now = clock()
                let tasks = try taskRepo.dueOn(date: now)
                let events = try gcalRepo.eventsOn(date: now)
                struct Item: Encodable {
                    let kind: String; let title: String
                    let start_at: String?; let due_at: String?
                    let category: String
                }
                let items: [Item] =
                    tasks.map {
                        Item(kind: "task", title: $0.title,
                             start_at: nil,
                             due_at: $0.dueAt.map(ISO8601DateFormatter().string(from:)),
                             category: $0.category)
                    } +
                    events.map {
                        Item(kind: "event", title: $0.title,
                             start_at: ISO8601DateFormatter().string(from: $0.startAt),
                             due_at: nil,
                             category: $0.category)
                    }
                struct Out: Encodable { let items: [Item] }
                let data = try JSONEncoder().encode(Out(items: items))
                return String(data: data, encoding: .utf8) ?? "{}"
            })
    }
}
