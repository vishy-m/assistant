import Foundation
import GRDB

public struct ClassPinRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func all(courseId: String) throws -> [ClassPin] {
        try db.queue.read { db in
            try ClassPin.filter(Column("course_id") == courseId)
                .order(Column("z_order")).fetchAll(db)
        }
    }

    public func upsert(_ pin: ClassPin) throws {
        try db.queue.write { db in
            var p = pin; p.updatedAt = Date(); try p.save(db)
        }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { db in try ClassPin.deleteOne(db, key: id) }
    }
}
