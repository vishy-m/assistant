import Foundation
import AssistantStore

public struct InsertEventPayload: Codable, Equatable {
    public let summary: String
    public let startISO: String
    public let endISO: String
    public let location: String?
    public let description: String?
    public let courseId: String?
    public let eventType: String?

    public init(summary: String, startISO: String, endISO: String,
                location: String?, description: String?,
                courseId: String? = nil, eventType: String? = nil) {
        self.summary = summary
        self.startISO = startISO
        self.endISO = endISO
        self.location = location
        self.description = description
        self.courseId = courseId
        self.eventType = eventType
    }

    enum CodingKeys: String, CodingKey {
        case summary, startISO, endISO, location, description, courseId, eventType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decode(String.self, forKey: .summary)
        startISO = try c.decode(String.self, forKey: .startISO)
        endISO = try c.decode(String.self, forKey: .endISO)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
    }
}

public enum OutboxPayload: Codable, Equatable {
    case insertEvent(InsertEventPayload)
    // Future: updateEvent, deleteEvent
}

public final actor OutboxProcessor {

    private let client: GCalClient
    private let db: AssistantDB
    private let quota: QuotaGuard
    private let repo: GCalRepository
    private let setting: SettingRepository

    public init(client: GCalClient, db: AssistantDB, quota: QuotaGuard) {
        self.client = client
        self.db = db
        self.quota = quota
        self.repo = GCalRepository(db: db)
        self.setting = SettingRepository(db: db)
    }

    public func drainOnce() async throws {
        let ops = try repo.pendingOps()
        for op in ops {
            // Exponential backoff: skip if attempted recently
            if let last = op.lastAttemptAt {
                let waitSec = min(pow(2.0, Double(op.attempts)), 3600)
                if Date().timeIntervalSince(last) < waitSec { continue }
            }
            guard try quota.tryConsume() else { return }
            do {
                try await execute(op)
                try repo.removeOp(id: op.id)
            } catch {
                try repo.markAttempt(opId: op.id)
                // Bubble GCalError.unauthorized to caller so they can prompt re-auth
                if case GCalError.unauthorized = error { throw error }
            }
        }
    }

    private func execute(_ op: PendingGCalOp) async throws {
        guard let data = op.payloadJson.data(using: .utf8) else {
            throw GCalError.decoding("payload not utf8")
        }
        let payload = try JSONDecoder().decode(OutboxPayload.self, from: data)
        switch payload {
        case .insertEvent(let p):
            guard let cal = try setting.get(AssistantCalendarBootstrap.settingKey) else {
                throw GCalError.notFound  // can't write without assistant calendar
            }
            let iso = ISO8601DateFormatter()
            guard let start = iso.date(from: p.startISO),
                  let end = iso.date(from: p.endISO) else {
                throw GCalError.decoding("bad ISO date")
            }
            let typeRow = try p.eventType.flatMap {
                try EventTypeRepository(db: db).find(id: $0)
            }
            var extProps: [String: String] = [:]
            if let courseId = p.courseId { extProps["assistant_course_id"] = courseId }
            if let eventType = p.eventType { extProps["assistant_event_type"] = eventType }
            _ = try await client.insertEvent(calendarId: cal,
                                             summary: p.summary,
                                             start: start, end: end,
                                             location: p.location,
                                             description: p.description,
                                             colorId: typeRow?.googleColorId,
                                             extendedProperties: extProps.isEmpty ? nil : extProps)
        }
    }
}
