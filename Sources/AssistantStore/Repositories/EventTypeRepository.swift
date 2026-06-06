import Foundation
import GRDB

public struct EventTypeRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func all() throws -> [EventType] {
        try db.queue.read { db in
            try EventType.order(Column("sort_order")).fetchAll(db)
        }
    }

    public func find(id: String) throws -> EventType? {
        try db.queue.read { db in try EventType.fetchOne(db, key: id) }
    }

    public func upsert(_ type: EventType) throws {
        try db.queue.write { db in try type.save(db) }
    }

    /// Built-in types may be recolored (via `upsert`) but never deleted.
    public func delete(id: String) throws {
        try db.queue.write { db in
            guard let existing = try EventType.fetchOne(db, key: id),
                  !existing.isBuiltin else { return }
            _ = try EventType.deleteOne(db, key: id)
        }
    }
}
