import Foundation
import GRDB

public struct BriefingRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func insert(_ b: Briefing) throws {
        try db.queue.write { db in try b.insert(db) }
    }

    public func find(id: String) throws -> Briefing? {
        try db.queue.read { db in try Briefing.fetchOne(db, key: id) }
    }

    public func recent(kind: String?, limit: Int) throws -> [Briefing] {
        try db.queue.read { db in
            var q = Briefing.order(Column("fired_at").desc).limit(limit)
            if let k = kind { q = q.filter(Column("kind") == k) }
            return try q.fetchAll(db)
        }
    }

    public func markDismissed(id: String) throws {
        try db.queue.write { db in
            try db.execute(sql: """
                UPDATE briefing_log SET dismissed_at = ? WHERE id = ?
            """, arguments: [Date(), id])
        }
    }

    public func markActedOn(id: String) throws {
        try db.queue.write { db in
            try db.execute(sql: """
                UPDATE briefing_log SET acted_on = 1, dismissed_at = ? WHERE id = ?
            """, arguments: [Date(), id])
        }
    }

    /// Used by sub-plan #6's Focus-mode drain: returns briefings that fired
    /// recently and have not been dismissed.
    public func pendingDelivery(since: Date) throws -> [Briefing] {
        try db.queue.read { db in
            try Briefing
                .filter(Column("fired_at") >= since)
                .filter(Column("dismissed_at") == nil)
                .order(Column("fired_at"))
                .fetchAll(db)
        }
    }

    // MARK: - Delivery (separate from dismissal)

    /// Side table recording which briefings the UI acknowledged. Created on
    /// demand so this doesn't need a schema migration.
    private static let createDeliveryTable = """
        CREATE TABLE IF NOT EXISTS briefing_delivery (
            id           TEXT PRIMARY KEY NOT NULL,
            delivered_at DATETIME NOT NULL
        )
        """

    /// Records that the UI acknowledged the briefing.
    public func markDelivered(id: String, at date: Date = Date()) throws {
        try db.queue.write { db in
            try db.execute(sql: Self.createDeliveryTable)
            try db.execute(sql: """
                INSERT INTO briefing_delivery (id, delivered_at) VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET delivered_at = excluded.delivered_at
                """, arguments: [id, date])
        }
    }

    public func deliveredAt(id: String) throws -> Date? {
        try db.queue.write { db in
            try db.execute(sql: Self.createDeliveryTable)
            return try Date.fetchOne(
                db, sql: "SELECT delivered_at FROM briefing_delivery WHERE id = ?",
                arguments: [id])
        }
    }

    /// Briefings fired since `since`, not dismissed, and never acknowledged
    /// by the UI. Oldest first.
    public func undelivered(since: Date) throws -> [Briefing] {
        try db.queue.write { db in
            try db.execute(sql: Self.createDeliveryTable)
            return try Briefing.fetchAll(db, sql: """
                SELECT briefing_log.* FROM briefing_log
                WHERE fired_at >= ?
                  AND dismissed_at IS NULL
                  AND NOT EXISTS (SELECT 1 FROM briefing_delivery d WHERE d.id = briefing_log.id)
                ORDER BY fired_at
                """, arguments: [since])
        }
    }
}
