import Foundation
import AssistantStore

public final actor GCalSyncWorker {

    /// Integer setting bumped when the Google account is disconnected or
    /// switched. A run that sees it change stops writing, so results fetched
    /// for the old account never land in the cache. Absent means 0.
    public static let accountGenerationKey = "gcal_account_generation"

    /// Minimum horizon advance worth a gap-fill request.
    static let horizonFillThreshold: TimeInterval = 86_400

    private let client: GCalClient
    private let db: AssistantDB
    private let quota: QuotaGuard
    private let clock: @Sendable () -> Date
    private let initialWindowDays: Int

    private let cacheRepo: GCalRepository
    private let syncState: SyncState
    private let setting: SettingRepository

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
        self.setting = SettingRepository(db: db)
    }

    public func runOnce() async throws {
        guard try quota.tryConsume() else { return }
        let generation = accountGeneration()
        let list = try await client.listCalendars()

        for cal in list.items {
            guard accountGeneration() == generation else { return }
            try await syncCalendar(id: cal.id, generation: generation)
        }
    }

    private func accountGeneration() -> Int {
        let value: Int? = try? setting.getCodable(Self.accountGenerationKey)
        return value ?? 0
    }

    private func syncCalendar(id: String, generation: Int) async throws {
        guard let token = try syncState.syncToken(for: id) else {
            try await fullSync(id: id, generation: generation)
            return
        }
        do {
            guard try await incrementalSync(id: id, token: token, generation: generation) else {
                return
            }
        } catch GCalError.syncTokenInvalid {
            // Keep the old token until the replacement snapshot is complete.
            try await fullSync(id: id, generation: generation)
            return
        }
        try await fillHorizon(id: id, generation: generation)
    }

    /// Change-only sync. Applies each page as it arrives and stores the new
    /// token from the last page. Returns false if it stopped early.
    private func incrementalSync(id: String, token: String, generation: Int) async throws -> Bool {
        var pageToken: String? = nil
        repeat {
            guard try quota.tryConsume() else { return false }
            let resp = try await client.listEvents(calendarId: id, syncToken: token,
                                                   pageToken: pageToken)
            guard accountGeneration() == generation else { return false }
            let (upserts, deletes) = changes(resp.items, calendarId: id,
                                             calendarTimeZone: resp.timeZone)
            try cacheRepo.applyRemote(calendarId: id, upserts: upserts, deletes: deletes)
            pageToken = resp.nextPageToken
            if let next = resp.nextSyncToken {
                try syncState.setSyncToken(id, token: next)
            }
        } while pageToken != nil
        return true
    }

    /// Windowed full sync: pages the whole window into memory, then replaces
    /// this calendar's in-window rows and stores the new token. If any page
    /// fails, the previous rows and token stay as they were.
    private func fullSync(id: String, generation: Int) async throws {
        let now = clock()
        let lo = now.addingTimeInterval(-86_400)
        let hi = horizon(from: now)
        guard let pages = try await fetchWindow(id: id, from: lo, to: hi) else { return }
        guard accountGeneration() == generation else { return }

        let (upserts, deletes) = changes(pages.items, calendarId: id,
                                         calendarTimeZone: pages.timeZone)
        try cacheRepo.replaceWindow(calendarId: id, start: lo, end: hi,
                                    upserts: upserts, deletes: deletes)
        if let next = pages.nextSyncToken {
            try syncState.setSyncToken(id, token: next)
        } else {
            try syncState.clearSyncToken(id)
        }
        try syncState.setCoverageEnd(id, end: hi)
    }

    /// Fetches `[coverageEnd, now + window)` without a sync token so events
    /// that were never edited still appear as the horizon moves forward. The
    /// gap response's token is discarded: it would narrow incremental sync to
    /// the gap. Calendars synced before coverage was tracked fill once from now.
    private func fillHorizon(id: String, generation: Int) async throws {
        let now = clock()
        let target = horizon(from: now)
        let from = try syncState.coverageEnd(for: id) ?? now.addingTimeInterval(-86_400)
        guard target.timeIntervalSince(from) >= Self.horizonFillThreshold else { return }
        guard let pages = try await fetchWindow(id: id, from: from, to: target) else { return }
        guard accountGeneration() == generation else { return }

        let (upserts, deletes) = changes(pages.items, calendarId: id,
                                         calendarTimeZone: pages.timeZone)
        try cacheRepo.applyRemote(calendarId: id, upserts: upserts, deletes: deletes)
        try syncState.setCoverageEnd(id, end: target)
    }

    private func horizon(from now: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: initialWindowDays, to: now)
            ?? now.addingTimeInterval(Double(initialWindowDays) * 86_400)
    }

    private struct WindowPages {
        var items: [GCalEvent] = []
        var timeZone: String?
        var nextSyncToken: String?
    }

    /// All pages of a time-bounded list. Nil when quota ran out part-way.
    private func fetchWindow(id: String, from: Date, to: Date) async throws -> WindowPages? {
        var out = WindowPages()
        var pageToken: String? = nil
        repeat {
            guard try quota.tryConsume() else { return nil }
            let resp = try await client.listEvents(calendarId: id, syncToken: nil,
                                                   timeMin: from, timeMax: to,
                                                   pageToken: pageToken)
            out.items += resp.items
            out.timeZone = out.timeZone ?? resp.timeZone
            if let next = resp.nextSyncToken { out.nextSyncToken = next }
            pageToken = resp.nextPageToken
        } while pageToken != nil
        return out
    }

    /// Maps remote events to cache rows and deletions.
    /// - Cancelled events are deleted, whether or not they still carry dates.
    /// - All-day events (`start.date` / exclusive `end.date`) span local midnights.
    /// - New rows take `assistant_category` from Google, else `Misc`; existing
    ///   rows keep their local category (enforced by the repository).
    private func changes(_ events: [GCalEvent], calendarId: String,
                         calendarTimeZone: String?) -> (upserts: [GCalEventCache], deletes: [String]) {
        var upserts: [GCalEventCache] = []
        var deletes: [String] = []
        for event in events {
            if event.status == "cancelled" {
                deletes.append(event.id)
                continue
            }
            guard let span = Self.span(of: event, calendarTimeZone: calendarTimeZone) else {
                continue
            }
            var rawObject: [String: Any] = [
                "id": event.id,
                "summary": event.summary ?? "",
                "description": event.description ?? ""
            ]
            if span.allDay { rawObject["allDay"] = true }
            let raw = (try? JSONSerialization.data(withJSONObject: rawObject)) ?? Data()
            let priv = event.extendedProperties?.privateProps
            upserts.append(GCalEventCache(
                gcalEventId: event.id,
                calendarId: calendarId,
                title: event.summary ?? "(no title)",
                startAt: span.start,
                endAt: span.end,
                location: event.location,
                category: priv?["assistant_category"] ?? "Misc",
                lastSyncedAt: clock(),
                rawJson: String(data: raw, encoding: .utf8) ?? "{}",
                recurringEventId: event.recurringEventId,
                courseId: priv?["assistant_course_id"],
                eventType: priv?["assistant_event_type"]))
        }
        return (upserts, deletes)
    }

    static func span(of event: GCalEvent,
                     calendarTimeZone: String?) -> (start: Date, end: Date, allDay: Bool)? {
        if let s = event.start?.dateTime, let e = event.end?.dateTime {
            return (s, e, false)
        }
        guard let sd = event.start?.date, let ed = event.end?.date else { return nil }
        let zoneName = event.start?.timeZone ?? calendarTimeZone
        let zone = zoneName.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let s = localMidnight(sd, in: zone), let e = localMidnight(ed, in: zone) else {
            return nil
        }
        return (s, e, true)
    }

    /// `yyyy-MM-dd` → 00:00 of that civil date in `zone`.
    static func localMidnight(_ civilDate: String, in zone: TimeZone) -> Date? {
        let parts = civilDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
