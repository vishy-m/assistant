import Foundation
import AssistantStore
import AssistantLLM

public enum GCalTools {

    public static func register(into registry: inout ToolRegistry,
                                client: GCalClient,
                                db: AssistantDB,
                                isOnline: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isOnline },
                                now: @escaping @Sendable () -> Date = { Date() }) {
        let gcalRepo = GCalRepository(db: db)

        registry.register(
            tool: LLMTool(
                name: "create_calendar_event",
                description: "Create a time-blocked event on the user's Assistant calendar (visible in Google Calendar / Notion Calendar).",
                inputSchema: #"""
                {
                  "type": "object",
                  "properties": {
                    "summary":  { "type": "string" },
                    "start":    { "type": "string", "description": "ISO 8601 datetime" },
                    "end":      { "type": "string", "description": "ISO 8601 datetime" },
                    "location": { "type": "string" },
                    "description": { "type": "string" },
                    "category": { "type": "string" }
                  },
                  "required": ["summary","start","end"]
                }
                """#),
            handler: { argsJSON in
                struct Args: Decodable {
                    let summary: String; let start: String; let end: String
                    let location: String?; let description: String?
                    let category: String?
                }
                let args = try JSONDecoder().decode(Args.self,
                                                    from: argsJSON.data(using: .utf8) ?? Data())
                guard let s = FlexibleDate.parse(args.start),
                      let e = FlexibleDate.parse(args.end) else {
                    return #"{"error":"bad ISO date"}"#
                }
                let writer = CalendarWriter(client: client, db: db, isOnline: isOnline)
                do {
                    let ev = try await writer.create(
                        title: args.summary, start: s, end: e,
                        location: args.location, description: args.description,
                        category: args.category ?? "Misc")
                    return #"{"id":"\#(ev.id)","status":"created"}"#
                } catch {
                    return #"{"status":"not_confirmed","note":"The calendar write failed or you are offline (\#(error)). It was queued for retry and is NOT on the calendar yet — do not tell the user it was added."}"#
                }
            })

        registry.register(
            tool: LLMTool(
                name: "list_calendar",
                description: "List calendar events from the local cache. range ∈ today (the current calendar day), this_week (today through the next 6 days), next_24h (events overlapping the next 24 hours). Default today.",
                inputSchema: #"{"type":"object","properties":{"range":{"type":"string"}}}"#),
            handler: { argsJSON in
                struct Args: Decodable { let range: String? }
                let args = (try? JSONDecoder().decode(Args.self,
                                                     from: argsJSON.data(using: .utf8) ?? Data()))
                let range = args?.range ?? "today"
                let now = now()
                let events: [GCalEventCache]
                // One overlap query per range, so a multi-day event appears once.
                switch range {
                case "today":
                    events = try gcalRepo.eventsOn(date: now)
                case "this_week":
                    let cal = Calendar.current
                    let start = cal.startOfDay(for: now)
                    let end = cal.date(byAdding: .day, value: 7, to: start)
                        ?? start.addingTimeInterval(7 * 86_400)
                    events = try gcalRepo.eventsOverlapping(start: start, end: end)
                case "next_24h":
                    events = try gcalRepo.eventsOverlapping(start: now,
                                                            end: now.addingTimeInterval(86_400))
                default:
                    return #"{"error":"unsupported range","supported":["today","this_week","next_24h"]}"#
                }
                struct Item: Encodable {
                    let title: String; let start_at: String; let end_at: String
                    let location: String?; let category: String
                }
                let items = events.map { e in
                    Item(title: e.title,
                         start_at: ISO8601DateFormatter().string(from: e.startAt),
                         end_at: ISO8601DateFormatter().string(from: e.endAt),
                         location: e.location, category: e.category)
                }
                struct Out: Encodable { let events: [Item] }
                let data = try JSONEncoder().encode(Out(events: items))
                return String(data: data, encoding: .utf8) ?? "{}"
            })
    }
}
