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

    public func all() throws -> [AssistantStore.Task] {
        try db.queue.read { db in
            try AssistantStore.Task.order(Column("due_at")).fetchAll(db)
        }
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

    /// Incomplete tasks with a `dueAt` in [start, end). Used by the calendar.
    public func dueInRange(start: Date, end: Date) throws -> [AssistantStore.Task] {
        try db.queue.read { db in
            try AssistantStore.Task
                .filter(Column("completed_at") == nil)
                .filter(Column("due_at") >= start && Column("due_at") < end)
                .order(Column("due_at"))
                .fetchAll(db)
        }
    }

    /// Updates one task's due date.
    public func setDueAt(id: String, dueAt: Date) throws {
        try db.queue.write { db in
            try db.execute(
                sql: "UPDATE task SET due_at = ?, updated_at = ? WHERE id = ?",
                arguments: [dueAt, Date(), id])
        }
    }

    /// Marks a task complete (now) or incomplete (clears the completion).
    public func setCompleted(id: String, completed: Bool) throws {
        try db.queue.write { db in
            try db.execute(
                sql: "UPDATE task SET completed_at = ?, updated_at = ? WHERE id = ?",
                arguments: [completed ? Date() : nil, Date(), id])
        }
    }

    /// Deletes every completed task.
    public func deleteCompleted() throws {
        try db.queue.write { db in
            try db.execute(sql: "DELETE FROM task WHERE completed_at IS NOT NULL")
        }
    }
}
