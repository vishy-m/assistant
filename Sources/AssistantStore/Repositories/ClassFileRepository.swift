import Foundation
import GRDB

public struct ClassFileRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func all(courseId: String) throws -> [ClassFile] {
        try db.queue.read { db in
            try ClassFile.filter(Column("course_id") == courseId)
                .order(Column("name")).fetchAll(db)
        }
    }

    public func find(id: String) throws -> ClassFile? {
        try db.queue.read { db in try ClassFile.fetchOne(db, key: id) }
    }

    public func create(_ file: ClassFile) throws {
        try db.queue.write { db in try file.insert(db) }
    }

    public func rename(id: String, name: String) throws {
        try db.queue.write { db in
            guard var f = try ClassFile.fetchOne(db, key: id) else { return }
            f.name = name; f.updatedAt = Date(); try f.update(db)
        }
    }

    public func move(id: String, toFolder folderId: String?) throws {
        try db.queue.write { db in
            guard var f = try ClassFile.fetchOne(db, key: id) else { return }
            f.folderId = folderId; f.updatedAt = Date(); try f.update(db)
        }
    }

    /// Deletes the file row + its pins; returns the `stored_name` so the caller
    /// (daemon) can remove the bytes. nil if the file didn't exist.
    @discardableResult
    public func delete(id: String) throws -> String? {
        try db.queue.write { db in
            guard let f = try ClassFile.fetchOne(db, key: id) else { return nil }
            try ClassPin.filter(Column("file_id") == id).deleteAll(db)
            try f.delete(db)
            return f.storedName
        }
    }
}
