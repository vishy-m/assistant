import Foundation
import AssistantStore
import AssistantShared

/// Single owner of calendar create/update/delete. Resolves the dedicated
/// "Assistant" calendar, writes through GCalClient, mirrors the local cache,
/// and enqueues to the outbox when offline or when an online write fails.
public final class CalendarWriter: Sendable {

    private let client: GCalClient
    private let db: AssistantDB
    private let isOnline: @Sendable () -> Bool

    public init(client: GCalClient,
                db: AssistantDB,
                isOnline: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isOnline }) {
        self.client = client
        self.db = db
        self.isOnline = isOnline
    }

    public enum WriteError: Error { case offlineNoCalendar, notFound }

    @discardableResult
    public func create(title: String, start: Date, end: Date,
                       location: String?, description: String?,
                       category: String = "Misc",
                       recurrence: RecurrenceRule? = nil,
                       courseId: String? = nil,
                       eventType: String? = nil) async throws -> WeekEvent {
        let bootstrap = AssistantCalendarBootstrap(client: client, db: db)
        let repo = GCalRepository(db: db)
        let resolvedCategory = try CategoryRepository(db: db).resolve(category)
        let colorId = GoogleEventColor.nearestColorId(toHex: resolvedCategory.colorHex)
        let rrule = recurrence.map { [$0.rruleString] }

        // Recurring create is online-only: the rule is expanded by Google and
        // the occurrences flow back through sync.
        if recurrence != nil && !isOnline() {
            throw WriteError.offlineNoCalendar
        }

        // A class event's color comes from its event type; otherwise category color.
        let typeRow = try eventType.flatMap { try EventTypeRepository(db: db).find(id: $0) }
        let effectiveColorId = typeRow?.googleColorId ?? colorId
        var extProps: [String: String] = [:]
        if let courseId { extProps["assistant_course_id"] = courseId }
        if let eventType { extProps["assistant_event_type"] = eventType }

        let calID: String
        if isOnline() {
            calID = try await bootstrap.ensureAssistantCalendar()
        } else if let cached = try bootstrap.cachedCalendarId() {
            calID = cached
        } else {
            throw WriteError.offlineNoCalendar
        }

        if isOnline() {
            do {
                let ev = try await client.insertEvent(
                    calendarId: calID, summary: title, start: start, end: end,
                    location: location, description: description,
                    colorId: effectiveColorId, recurrence: rrule,
                    extendedProperties: extProps)
                // For a recurring master we do NOT cache a row: Google does not
                // return the master under singleEvents=true, so a cached master
                // would linger as a phantom duplicate. The expanded instances
                // arrive via the next sync instead.
                if recurrence == nil {
                    try repo.upsert(GCalEventCache(
                        gcalEventId: ev.id, calendarId: calID,
                        title: ev.summary ?? title, startAt: start, endAt: end,
                        location: location, category: resolvedCategory.name,
                        lastSyncedAt: Date(), rawJson: "{}",
                        recurringEventId: nil,
                        courseId: courseId, eventType: eventType))
                }
                return WeekEvent(id: ev.id, title: ev.summary ?? title,
                                 startAt: start, endAt: end,
                                 category: resolvedCategory.name, location: location,
                                 isRecurring: recurrence != nil,
                                 courseId: courseId, eventType: eventType)
            } catch {
                // Only one-off events queue offline; recurring failures surface.
                if recurrence == nil {
                    try enqueueInsert(title: title, start: start, end: end,
                                      location: location, description: description,
                                      courseId: courseId, eventType: eventType, repo: repo)
                }
                throw error
            }
        }
        try enqueueInsert(title: title, start: start, end: end,
                          location: location, description: description,
                          courseId: courseId, eventType: eventType, repo: repo)
        throw WriteError.offlineNoCalendar
    }

    public func update(eventId: String, start: Date, end: Date) async throws {
        let repo = GCalRepository(db: db)
        guard let cached = try repo.find(id: eventId) else { throw WriteError.notFound }
        let ev = try await client.updateEvent(
            calendarId: cached.calendarId, eventId: eventId,
            summary: nil, start: start, end: end, location: nil, description: nil)
        var updated = cached
        updated.startAt = start
        updated.endAt = end
        updated.title = ev.summary ?? cached.title
        updated.lastSyncedAt = Date()
        try repo.upsert(updated)
    }

    /// Assign or change an event's class and event type. Patches Google's
    /// extended properties + color, then mirrors the local cache.
    public func updateClassification(eventId: String,
                                     courseId: String?,
                                     eventType: String?) async throws {
        let repo = GCalRepository(db: db)
        guard let cached = try repo.find(id: eventId) else { throw WriteError.notFound }

        let typeRow = try eventType.flatMap { try EventTypeRepository(db: db).find(id: $0) }
        // Color precedence (matches create): event-type color wins, else the
        // event's category color. Always resolve a concrete colorId so clearing
        // the type resets Google's color instead of leaving the old one stale.
        let categoryColorId = GoogleEventColor.nearestColorId(
            toHex: try CategoryRepository(db: db).resolve(cached.category).colorHex)
        let effectiveColorId = typeRow?.googleColorId ?? categoryColorId
        // Always send both keys; nil clears them on Google (JSON null) so the
        // classification doesn't get re-applied on the next sync.
        let extProps: [String: String?] = [
            "assistant_course_id": courseId,
            "assistant_event_type": eventType
        ]

        // Response intentionally discarded: the next sync reconciles the cache
        // from Google. Online-only — no outbox/offline support this phase.
        _ = try await client.updateEvent(
            calendarId: cached.calendarId, eventId: eventId,
            summary: nil, start: nil, end: nil, location: nil, description: nil,
            colorId: effectiveColorId, extendedProperties: extProps)

        var updated = cached
        updated.courseId = courseId
        updated.eventType = eventType
        updated.lastSyncedAt = Date()
        try repo.upsert(updated)
    }

    public func delete(eventId: String) async throws {
        let repo = GCalRepository(db: db)
        guard let cached = try repo.find(id: eventId) else { throw WriteError.notFound }

        // Whole-series semantics: deleting any instance deletes the recurring
        // master on Google and purges every cached row for that series.
        if let masterId = cached.recurringEventId {
            do {
                try await client.deleteEvent(calendarId: cached.calendarId, eventId: masterId)
            } catch GCalError.notFound {
                // Already gone on Google — still purge locally.
            }
            try repo.deleteCachedSeries(recurringEventId: masterId)
            return
        }

        do {
            try await client.deleteEvent(calendarId: cached.calendarId, eventId: eventId)
        } catch GCalError.notFound {
            // Already gone on Google (deleted elsewhere, or a stale cache row) —
            // still purge it locally so it stops reappearing.
        }
        try repo.deleteCached(id: eventId)
    }

    private func enqueueInsert(title: String, start: Date, end: Date,
                               location: String?, description: String?,
                               courseId: String?, eventType: String?,
                               repo: GCalRepository) throws {
        let iso = ISO8601DateFormatter()
        let payload = OutboxPayload.insertEvent(InsertEventPayload(
            summary: title,
            startISO: iso.string(from: start),
            endISO: iso.string(from: end),
            location: location,
            description: description,
            courseId: courseId,
            eventType: eventType))
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"
        try repo.enqueue(PendingGCalOp(
            id: UUID().uuidString, opType: "insert_event",
            payloadJson: json, attempts: 0, lastAttemptAt: nil, createdAt: Date()))
    }
}
