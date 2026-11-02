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

    /// Deletes the course and, in the same transaction, its class pins, files
    /// and folders (those tables have no foreign key to `course`). Returns the
    /// removed file rows so the caller can clean up any bytes it has not
    /// already removed.
    @discardableResult
    public func delete(id: String) throws -> [ClassFile] {
        try db.queue.write { db in
            let files = try ClassFile.filter(Column("course_id") == id).fetchAll(db)
            try ClassPin.filter(Column("course_id") == id).deleteAll(db)
            try ClassFile.filter(Column("course_id") == id).deleteAll(db)
            try ClassFolder.filter(Column("course_id") == id).deleteAll(db)
            try Course.deleteOne(db, key: id)
            return files
        }
    }
}
