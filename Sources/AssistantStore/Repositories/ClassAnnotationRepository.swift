import Foundation
import GRDB

public struct ClassAnnotationRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func all(courseId: String) throws -> [ClassAnnotation] {
        try db.queue.read { db in
            try ClassAnnotation.filter(Column("course_id") == courseId)
                .order(Column("z_order")).fetchAll(db)
        }
    }

    public func upsert(_ annotation: ClassAnnotation) throws {
        try db.queue.write { db in
            var a = annotation; a.updatedAt = Date(); try a.save(db)
        }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { db in try ClassAnnotation.deleteOne(db, key: id) }
    }
}
