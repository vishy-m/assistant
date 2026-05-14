import Foundation
import GRDB

public struct GradeItem: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "grade_item"

    public var id: String
    public var courseId: String
    public var categoryId: String?
    public var name: String
    public var maxPoints: Double
    public var earnedPoints: Double?
    public var dueAt: Date?
    public var isExtraCredit: Bool
    public var weightOverridePct: Double?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, courseId: String, categoryId: String?, name: String,
                maxPoints: Double, earnedPoints: Double?, dueAt: Date?,
                isExtraCredit: Bool, weightOverridePct: Double?,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.courseId = courseId
        self.categoryId = categoryId
        self.name = name
        self.maxPoints = maxPoints
        self.earnedPoints = earnedPoints
        self.dueAt = dueAt
        self.isExtraCredit = isExtraCredit
        self.weightOverridePct = weightOverridePct
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case courseId = "course_id"
        case categoryId = "category_id"
        case maxPoints = "max_points"
        case earnedPoints = "earned_points"
        case dueAt = "due_at"
        case isExtraCredit = "is_extra_credit"
        case weightOverridePct = "weight_override_pct"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
