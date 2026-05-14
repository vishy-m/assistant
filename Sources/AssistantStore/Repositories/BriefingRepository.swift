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
}
