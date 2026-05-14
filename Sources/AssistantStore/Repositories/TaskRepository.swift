import Foundation
import GRDB

public struct TaskRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func insert(_ t: AssistantStore.Task) throws {
        try db.queue.write { db in try t.insert(db) }
    }

    public func update(_ t: AssistantStore.Task) throws {
        var task = t
        task.updatedAt = Date()
        try db.queue.write { db in try task.update(db) }
    }

    public func find(id: String) throws -> AssistantStore.Task? {
        try db.queue.read { db in try AssistantStore.Task.fetchOne(db, key: id) }
    }

    public func dueOn(date: Date) throws -> [AssistantStore.Task] {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        return try db.queue.read { db in
            try AssistantStore.Task
                .filter(Column("due_at") >= start && Column("due_at") < end)
                .filter(Column("completed_at") == nil)
                .order(Column("due_at"))
                .fetchAll(db)
        }
    }

    public func overdue(asOf date: Date = Date()) throws -> [AssistantStore.Task] {
        try db.queue.read { db in
            try AssistantStore.Task
                .filter(Column("due_at") < date)
                .filter(Column("completed_at") == nil)
                .order(Column("due_at"))
                .fetchAll(db)
        }
    }

    public func complete(id: String) throws {
        try db.queue.write { db in
            try db.execute(sql: """
                UPDATE task SET completed_at = ?, updated_at = ? WHERE id = ?
            """, arguments: [Date(), Date(), id])
        }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { db in
            try AssistantStore.Task.deleteOne(db, key: id)
        }
    }
}
