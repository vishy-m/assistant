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

    public func find(id: String) throws -> GCalEventCache? {
        try db.queue.read { db in
            try GCalEventCache.fetchOne(db, key: id)
        }
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

    public func deleteCached(id: String) throws {
        _ = try db.queue.write { db in
            try GCalEventCache.deleteOne(db, key: id)
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

    public func removeOp(id: String) throws {
        _ = try db.queue.write { db in
            try PendingGCalOp.deleteOne(db, key: id)
        }
    }
}
