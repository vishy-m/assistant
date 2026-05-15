import Foundation
import AssistantStore

public struct InsertEventPayload: Codable, Equatable {
    public let summary: String
    public let startISO: String
    public let endISO: String
    public let location: String?
    public let description: String?

    public init(summary: String, startISO: String, endISO: String,
                location: String?, description: String?) {
        self.summary = summary
        self.startISO = startISO
        self.endISO = endISO
        self.location = location
        self.description = description
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
            _ = try await client.insertEvent(calendarId: cal,
                                             summary: p.summary,
                                             start: start, end: end,
                                             location: p.location,
                                             description: p.description)
        }
    }
}
