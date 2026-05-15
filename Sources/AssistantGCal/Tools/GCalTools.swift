import Foundation
import AssistantStore
import AssistantLLM

public enum GCalTools {

    public static func register(into registry: inout ToolRegistry,
                                client: GCalClient,
                                db: AssistantDB,
                                isOnline: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isOnline }) {
        let gcalRepo = GCalRepository(db: db)
        let setting = SettingRepository(db: db)

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
                let iso = ISO8601DateFormatter()
                guard let s = iso.date(from: args.start), let e = iso.date(from: args.end) else {
                    return #"{"error":"bad ISO date"}"#
                }
                guard let calID = try setting.get(AssistantCalendarBootstrap.settingKey) else {
                    return #"{"error":"Assistant calendar not initialized — connect Google Calendar first."}"#
                }

                if isOnline() {
                    do {
                        let ev = try await client.insertEvent(
                            calendarId: calID, summary: args.summary,
                            start: s, end: e, location: args.location,
                            description: args.description)
                        try gcalRepo.upsert(GCalEventCache(
                            gcalEventId: ev.id, calendarId: calID, title: ev.summary ?? args.summary,
                            startAt: s, endAt: e, location: args.location,
                            category: args.category ?? "generic",
                            lastSyncedAt: Date(), rawJson: "{}"))
                        return #"{"id":"\#(ev.id)","status":"created"}"#
                    } catch {
                        // Fall through to enqueue
                    }
                }
                // Offline or write failed → enqueue
                let payload = OutboxPayload.insertEvent(InsertEventPayload(
                    summary: args.summary,
                    startISO: iso.string(from: s),
                    endISO: iso.string(from: e),
                    location: args.location,
                    description: args.description))
                let payloadJSON = String(
                    data: try JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"
                try gcalRepo.enqueue(PendingGCalOp(
                    id: UUID().uuidString, opType: "insert_event",
                    payloadJson: payloadJSON, attempts: 0,
                    lastAttemptAt: nil, createdAt: Date()))
                return #"{"status":"queued","note":"offline — will sync"}"#
            })

        registry.register(
            tool: LLMTool(
                name: "list_calendar",
                description: "List calendar events from the local cache. range ∈ today, this_week, next_24h",
                inputSchema: #"{"type":"object","properties":{"range":{"type":"string"}}}"#),
            handler: { argsJSON in
                struct Args: Decodable { let range: String? }
                let args = (try? JSONDecoder().decode(Args.self,
                                                     from: argsJSON.data(using: .utf8) ?? Data()))
                let range = args?.range ?? "today"
                let now = Date()
                let events: [GCalEventCache]
                switch range {
                case "this_week":
                    let cal = Calendar(identifier: .gregorian)
                    let end = cal.date(byAdding: .day, value: 7, to: now) ?? now
                    events = try (try gcalRepo.eventsOn(date: now)) + (try gcalRepo.eventsOn(date: end))
                case "next_24h":
                    events = try gcalRepo.eventsOn(date: now)
                default:
                    events = try gcalRepo.eventsOn(date: now)
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
