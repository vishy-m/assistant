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
    /// Client-minted Google event id, reused on every replay so a retry of an
    /// insert Google already accepted cannot duplicate it. Nil on rows queued
    /// before ids were minted; the processor assigns one before the first send.
    public let eventId: String?
    /// Local category name, sent as `assistant_category` so sync can restore it.
    public let category: String?

    public init(summary: String, startISO: String, endISO: String,
                location: String?, description: String?,
                courseId: String? = nil, eventType: String? = nil,
                eventId: String? = nil, category: String? = nil) {
        self.summary = summary
        self.startISO = startISO
        self.endISO = endISO
        self.location = location
        self.description = description
        self.courseId = courseId
        self.eventType = eventType
        self.eventId = eventId
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case summary, startISO, endISO, location, description, courseId, eventType
        case eventId, category
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
        eventId = try c.decodeIfPresent(String.self, forKey: .eventId)
        category = try c.decodeIfPresent(String.self, forKey: .category)
    }

    func withEventId(_ id: String) -> InsertEventPayload {
        InsertEventPayload(summary: summary, startISO: startISO, endISO: endISO,
                           location: location, description: description,
                           courseId: courseId, eventType: eventType,
                           eventId: id, category: category)
    }
}

public enum OutboxPayload: Codable, Equatable {
    case insertEvent(InsertEventPayload)
    // Future: updateEvent, deleteEvent
}

public final actor OutboxProcessor {

    /// Attempts after which an op that keeps failing permanently is dropped.
    static let maxPermanentAttempts = 8

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
                let ready = try assignEventIdIfMissing(op)
                try await execute(ready)
                try repo.removeOp(id: op.id)
            } catch {
                try repo.markAttempt(opId: op.id)
                // Bubble GCalError.unauthorized to caller so they can prompt re-auth
                if case GCalError.unauthorized = error { throw error }
                if let kind = Self.permanentFailureKind(error),
                   op.attempts + 1 >= Self.maxPermanentAttempts {
                    NSLog("[OutboxProcessor] dropping op \(op.id) after \(op.attempts + 1) attempts: \(kind)")
                    try repo.removeOp(id: op.id)
                }
            }
        }
    }

    /// Errors that a retry will not fix. Returns a log-safe name, no payload.
    static func permanentFailureKind(_ error: Error) -> String? {
        switch error {
        case GCalError.forbidden: return "forbidden"
        case GCalError.notFound: return "notFound"
        case GCalError.decoding: return "decoding"
        case is DecodingError: return "payloadDecoding"
        default: return nil
        }
    }

    /// Legacy rows have no event id. Mint one and store it before the first
    /// send, so every later replay of this op uses the same id.
    private func assignEventIdIfMissing(_ op: PendingGCalOp) throws -> PendingGCalOp {
        guard let data = op.payloadJson.data(using: .utf8),
              case .insertEvent(let p) = try JSONDecoder().decode(OutboxPayload.self, from: data),
              p.eventId == nil else { return op }
        let json = String(data: try JSONEncoder().encode(
            OutboxPayload.insertEvent(p.withEventId(GCalEventID.mint()))), encoding: .utf8) ?? "{}"
        try repo.updateOpPayload(id: op.id, payloadJson: json)
        var updated = op
        updated.payloadJson = json
        return updated
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
            // Event-type color is applied on replay; category color is not
            // re-derived offline, so non-class offline events replay without a
            // colorId — a pre-existing limitation. The category name itself is
            // carried as `assistant_category`.
            let typeRow = try p.eventType.flatMap {
                try EventTypeRepository(db: db).find(id: $0)
            }
            var extProps: [String: String] = [:]
            if let courseId = p.courseId { extProps["assistant_course_id"] = courseId }
            if let eventType = p.eventType { extProps["assistant_event_type"] = eventType }
            if let category = p.category { extProps["assistant_category"] = category }
            do {
                _ = try await client.insertEvent(eventId: p.eventId,
                                                 calendarId: cal,
                                                 summary: p.summary,
                                                 start: start, end: end,
                                                 location: p.location,
                                                 description: p.description,
                                                 colorId: typeRow?.googleColorId,
                                                 extendedProperties: extProps.isEmpty ? nil : extProps)
            } catch GCalError.conflict {
                // An earlier attempt already created this id. Confirm it exists.
                guard let id = p.eventId else { throw GCalError.conflict }
                _ = try await client.getEvent(calendarId: cal, eventId: id)
            }
        }
    }
}
