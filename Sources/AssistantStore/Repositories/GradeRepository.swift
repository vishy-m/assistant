import Foundation
import GRDB

public enum GradeWriteError: Error, Equatable {
    case nonFinitePoints
    case maxPointsNotPositive
    case weightOutOfRange
    case courseChangeRejected
    case categoryInUse
}

public enum GradeWriteRules {
    /// Weights the editor accepts. 0 and 100 are included. 100.5 is not.
    public static let weightBounds: ClosedRange<Double> = 0...100

    public static func isSavableWeight(_ weight: Double) -> Bool {
        weight.isFinite && weightBounds.contains(weight)
    }

    /// Regular and extra-credit items both need a finite max above 0.
    /// A nil earned score is an ungraded item and is allowed.
    /// Rows already stored with a bad max are left for the calculator to skip.
    public static func isSavableItem(maxPoints: Double, earnedPoints: Double?) -> Bool {
        (try? validateItem(maxPoints: maxPoints, earnedPoints: earnedPoints)) != nil
    }

    public static func validateWeight(_ weight: Double) throws {
        guard isSavableWeight(weight) else { throw GradeWriteError.weightOutOfRange }
    }

    public static func validateItem(maxPoints: Double, earnedPoints: Double?) throws {
        if !maxPoints.isFinite || earnedPoints?.isFinite == false {
            throw GradeWriteError.nonFinitePoints
        }
        guard maxPoints > 0 else { throw GradeWriteError.maxPointsNotPositive }
    }
}

public struct GradeRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    // Categories
    public func insertCategory(_ c: GradeCategory) throws {
        try GradeWriteRules.validateWeight(c.weightPct)
        try db.queue.write { db in try c.insert(db) }
    }
    public func updateCategory(_ c: GradeCategory) throws {
        try GradeWriteRules.validateWeight(c.weightPct)
        try db.queue.write { db in try c.update(db) }
    }
    public func deleteCategory(id: String) throws {
        try db.queue.write { db in
            let remaining = try GradeItem.filter(Column("category_id") == id).fetchCount(db)
            if remaining > 0 { throw GradeWriteError.categoryInUse }
            _ = try GradeCategory.deleteOne(db, key: id)
        }
    }
    public func categories(forCourse courseId: String) throws -> [GradeCategory] {
        try db.queue.read { db in
            try GradeCategory.filter(Column("course_id") == courseId).fetchAll(db)
        }
    }

    // Items
    public func insertItem(_ i: GradeItem) throws {
        try GradeWriteRules.validateItem(maxPoints: i.maxPoints, earnedPoints: i.earnedPoints)
        try db.queue.write { db in try i.insert(db) }
    }
    public func updateItem(_ i: GradeItem) throws {
        try GradeWriteRules.validateItem(maxPoints: i.maxPoints, earnedPoints: i.earnedPoints)
        try db.queue.write { db in
            if let stored = try GradeItem.fetchOne(db, key: i.id), stored.courseId != i.courseId {
                throw GradeWriteError.courseChangeRejected
            }
            var item = i
            item.updatedAt = Date()
            try item.update(db)
        }
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
        guard earned.isFinite else { throw GradeWriteError.nonFinitePoints }
        try db.queue.write { db in
            try db.execute(sql: """
                UPDATE grade_item
                SET earned_points = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [earned, Date(), itemId])
        }
    }
}
