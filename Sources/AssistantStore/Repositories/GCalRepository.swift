import Foundation
import GRDB

public struct GCalRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    // Cache
    public func upsert(_ e: GCalEventCache) throws {
        try db.queue.write { db in
            try e.save(db)
        }
    }

    /// Unscoped lookup by event id. Ids are unique per calendar only, so this
    /// returns nil when more than one calendar has the id (fails closed rather
    /// than acting on the wrong calendar). Prefer `find(calendarId:eventId:)`.
    public func find(id: String) throws -> GCalEventCache? {
        try db.queue.read { db in
            let rows = try GCalEventCache
                .filter(Column("gcal_event_id") == id)
                .limit(2)
                .fetchAll(db)
            return rows.count == 1 ? rows[0] : nil
        }
    }

    public func find(calendarId: String, eventId: String) throws -> GCalEventCache? {
        try db.queue.read { db in
            try GCalEventCache.fetchOne(db, key: Self.key(calendarId, eventId))
        }
    }

    private static func key(_ calendarId: String, _ eventId: String) -> [String: String] {
        ["calendar_id": calendarId, "gcal_event_id": eventId]
    }

    public func eventsOn(date: Date) throws -> [GCalEventCache] {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try db.queue.read { db in
            try GCalEventCache
                .filter(Column("start_at") < end && Column("end_at") > start)
                .order(Column("start_at"))
                .fetchAll(db)
        }
    }

    /// Events overlapping the half-open interval `[start, end)`, ordered by start.
    public func eventsOverlapping(start: Date, end: Date) throws -> [GCalEventCache] {
        try db.queue.read { db in
            try GCalEventCache
                .filter(Column("start_at") < end && Column("end_at") > start)
                .order(Column("start_at"))
                .fetchAll(db)
        }
    }

    /// All cached events linked to a course, ordered by start time.
    public func eventsForCourse(_ courseId: String) throws -> [GCalEventCache] {
        try db.queue.read { db in
            try GCalEventCache
                .filter(Column("course_id") == courseId)
                .order(Column("start_at"))
                .fetchAll(db)
        }
    }

    /// Unscoped delete. Deletes nothing when the id exists on more than one
    /// calendar. Prefer `deleteCached(calendarId:eventId:)`.
    public func deleteCached(id: String) throws {
        try db.queue.write { db in
            try db.execute(sql: """
                DELETE FROM gcal_event_cache
                WHERE gcal_event_id = ?
                  AND (SELECT COUNT(*) FROM gcal_event_cache WHERE gcal_event_id = ?) = 1
                """, arguments: [id, id])
        }
    }

    public func deleteCached(calendarId: String, eventId: String) throws {
        _ = try db.queue.write { db in
            try GCalEventCache.deleteOne(db, key: Self.key(calendarId, eventId))
        }
    }

    /// Deletes every cached row belonging to a recurring series — both the
    /// expanded instances (matched by `recurring_event_id`) and the master row
    /// itself (matched by `gcal_event_id`).
    public func deleteCachedSeries(recurringEventId: String) throws {
        try db.queue.write { db in
            try db.execute(
                sql: "DELETE FROM gcal_event_cache WHERE recurring_event_id = ? OR gcal_event_id = ?",
                arguments: [recurringEventId, recurringEventId])
        }
    }

    /// Calendar-scoped form of `deleteCachedSeries(recurringEventId:)`.
    public func deleteCachedSeries(calendarId: String, recurringEventId: String) throws {
        try db.queue.write { db in
            try Self.deleteSeries(db, calendarId: calendarId, id: recurringEventId)
        }
    }

    private static func deleteSeries(_ db: Database, calendarId: String, id: String) throws {
        try db.execute(sql: """
            DELETE FROM gcal_event_cache
            WHERE calendar_id = ? AND (gcal_event_id = ? OR recurring_event_id = ?)
            """, arguments: [calendarId, id, id])
    }

    // Sync application

    /// Applies one batch of remote changes for a calendar in one transaction.
    /// `deletes` are event ids; deleting an id also drops cached instances whose
    /// `recurring_event_id` is that id (a cancelled series master).
    /// An existing row keeps its local `category`: Google does not own it.
    public func applyRemote(calendarId: String,
                            upserts: [GCalEventCache],
                            deletes: [String]) throws {
        try db.queue.write { db in
            try Self.apply(db, calendarId: calendarId, upserts: upserts, deletes: deletes)
        }
    }

    /// Full-snapshot form of `applyRemote`: also deletes this calendar's rows
    /// that overlap `[start, end)` and are absent from `upserts`. Rows outside
    /// the window and rows of other calendars are untouched. All in one transaction.
    public func replaceWindow(calendarId: String, start: Date, end: Date,
                              upserts: [GCalEventCache],
                              deletes: [String]) throws {
        try db.queue.write { db in
            let keep = Set(upserts.map(\.gcalEventId))
            let inWindow = try String.fetchAll(db, sql: """
                SELECT gcal_event_id FROM gcal_event_cache
                WHERE calendar_id = ? AND start_at < ? AND end_at > ?
                """, arguments: [calendarId, end, start])
            for id in inWindow where !keep.contains(id) {
                _ = try GCalEventCache.deleteOne(db, key: Self.key(calendarId, id))
            }
            try Self.apply(db, calendarId: calendarId, upserts: upserts, deletes: deletes)
        }
    }

    private static func apply(_ db: Database, calendarId: String,
                              upserts: [GCalEventCache], deletes: [String]) throws {
        for id in deletes {
            try deleteSeries(db, calendarId: calendarId, id: id)
        }
        for var row in upserts {
            if let existing = try GCalEventCache.fetchOne(
                db, key: key(row.calendarId, row.gcalEventId)) {
                row.category = existing.category
            }
            try row.save(db)
        }
    }

    // Outbox
    public func enqueue(_ op: PendingGCalOp) throws {
        try db.queue.write { db in try op.insert(db) }
    }

    public func pendingOps() throws -> [PendingGCalOp] {
        try db.queue.read { db in
            try PendingGCalOp.order(Column("created_at")).fetchAll(db)
        }
    }

    public func markAttempt(opId: String) throws {
        try db.queue.write { db in
            try db.execute(sql: """
                UPDATE pending_gcal_op
                SET attempts = attempts + 1, last_attempt_at = ?
                WHERE id = ?
            """, arguments: [Date(), opId])
        }
    }

    public func updateOpPayload(id: String, payloadJson: String) throws {
        try db.queue.write { db in
            try db.execute(sql: "UPDATE pending_gcal_op SET payload_json = ? WHERE id = ?",
                           arguments: [payloadJson, id])
        }
    }

    public func removeOp(id: String) throws {
        _ = try db.queue.write { db in
            try PendingGCalOp.deleteOne(db, key: id)
        }
    }
}
