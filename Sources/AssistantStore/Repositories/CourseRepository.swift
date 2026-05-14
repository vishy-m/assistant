import Foundation
import GRDB

public struct CourseRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func insert(_ course: Course) throws {
        try db.queue.write { db in try course.insert(db) }
    }

    public func update(_ course: Course) throws {
        var c = course
        c.updatedAt = Date()
        try db.queue.write { db in try c.update(db) }
    }

    public func find(id: String) throws -> Course? {
        try db.queue.read { db in try Course.fetchOne(db, key: id) }
    }

    public func all() throws -> [Course] {
        try db.queue.read { db in try Course.fetchAll(db) }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { db in try Course.deleteOne(db, key: id) }
    }
}
