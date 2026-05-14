import Foundation
import AssistantStore

public final actor GCalSyncWorker {

    private let client: GCalClient
    private let db: AssistantDB
    private let quota: QuotaGuard
    private let clock: @Sendable () -> Date
    private let initialWindowDays: Int

    private let cacheRepo: GCalRepository
    private let syncState: SyncState

    public init(client: GCalClient,
                db: AssistantDB,
                quota: QuotaGuard,
                clock: @escaping @Sendable () -> Date = { Date() },
                initialWindowDays: Int = 60) {
        self.client = client
        self.db = db
        self.quota = quota
        self.clock = clock
        self.initialWindowDays = initialWindowDays
        self.cacheRepo = GCalRepository(db: db)
        self.syncState = SyncState(db: db)
    }

    public func runOnce() async throws {
        guard try quota.tryConsume() else { return }
        let list = try await client.listCalendars()

        for cal in list.items {
            try await syncCalendar(id: cal.id)
        }
    }

    private func syncCalendar(id: String) async throws {
        var pageToken: String? = nil
        let existingSync = try syncState.syncToken(for: id)
        var currentSyncToken = existingSync
        var usedFullSync = (existingSync == nil)
        var retryAfterInvalidToken = false

        repeat {
            retryAfterInvalidToken = false
            guard try quota.tryConsume() else { return }
            do {
                let resp: GCalEventList
                if let tok = currentSyncToken, !usedFullSync {
                    resp = try await client.listEvents(calendarId: id,
                                                       syncToken: tok,
                                                       pageToken: pageToken)
                } else {
                    let now = clock()
                    let end = Calendar(identifier: .gregorian)
                        .date(byAdding: .day, value: initialWindowDays, to: now)
                    resp = try await client.listEvents(calendarId: id,
                                                       syncToken: nil,
                                                       timeMin: now.addingTimeInterval(-86_400),
                                                       timeMax: end,
                                                       pageToken: pageToken)
                }
                for event in resp.items {
                    try persistEvent(event, calendarId: id)
                }
                pageToken = resp.nextPageToken
                if let next = resp.nextSyncToken {
                    try syncState.setSyncToken(id, token: next)
                    currentSyncToken = next
                }
            } catch GCalError.syncTokenInvalid {
                try syncState.clearSyncToken(id)
                currentSyncToken = nil
                usedFullSync = true
                pageToken = nil
                retryAfterInvalidToken = true
                continue
            }
        } while pageToken != nil || retryAfterInvalidToken
    }

    private func persistEvent(_ event: GCalEvent, calendarId: String) throws {
        // Skip events without a start/end (rare — recurring exceptions, etc.)
        guard let start = event.start?.dateTime, let end = event.end?.dateTime else {
            // Could be cancelled or all-day; if cancelled, delete from cache.
            if event.status == "cancelled" {
                try cacheRepo.deleteCached(id: event.id)
            }
            return
        }
        let raw = (try? JSONSerialization.data(withJSONObject: [
            "id": event.id,
            "summary": event.summary ?? "",
            "description": event.description ?? ""
        ])) ?? Data()
        let cached = GCalEventCache(
            gcalEventId: event.id,
            calendarId: calendarId,
            title: event.summary ?? "(no title)",
            startAt: start,
            endAt: end,
            location: event.location,
            category: "generic",
            lastSyncedAt: clock(),
            rawJson: String(data: raw, encoding: .utf8) ?? "{}")
        try cacheRepo.upsert(cached)
    }
}
