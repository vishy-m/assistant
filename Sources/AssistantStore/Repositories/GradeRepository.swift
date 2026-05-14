import Foundation
import GRDB

public struct GradeRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    // Categories
    public func insertCategory(_ c: GradeCategory) throws {
        try db.queue.write { db in try c.insert(db) }
    }
    public func updateCategory(_ c: GradeCategory) throws {
        try db.queue.write { db in try c.update(db) }
    }
    public func deleteCategory(id: String) throws {
        _ = try db.queue.write { db in try GradeCategory.deleteOne(db, key: id) }
    }
    public func categories(forCourse courseId: String) throws -> [GradeCategory] {
        try db.queue.read { db in
            try GradeCategory.filter(Column("course_id") == courseId).fetchAll(db)
        }
    }

    // Items
    public func insertItem(_ i: GradeItem) throws {
        try db.queue.write { db in try i.insert(db) }
    }
    public func updateItem(_ i: GradeItem) throws {
        var item = i
        item.updatedAt = Date()
        try db.queue.write { db in try item.update(db) }
    }
    public func deleteItem(id: String) throws {
        _ = try db.queue.write { db in try GradeItem.deleteOne(db, key: id) }
    }
    public func findItem(id: String) throws -> GradeItem? {
        try db.queue.read { db in try GradeItem.fetchOne(db, key: id) }
    }
    public func items(forCourse courseId: String) throws -> [GradeItem] {
        try db.queue.read { db in
            try GradeItem.filter(Column("course_id") == courseId).fetchAll(db)
        }
    }
    public func items(forCategory categoryId: String) throws -> [GradeItem] {
        try db.queue.read { db in
            try GradeItem.filter(Column("category_id") == categoryId).fetchAll(db)
        }
    }
    public func setEarnedPoints(itemId: String, earned: Double) throws {
        try db.queue.write { db in
            try db.execute(sql: """
                UPDATE grade_item
                SET earned_points = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [earned, Date(), itemId])
        }
    }
}
