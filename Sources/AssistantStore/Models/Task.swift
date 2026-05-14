import Foundation
import GRDB

public struct Task: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "task"

    public var id: String
    public var title: String
    public var notes: String?
    public var dueAt: Date?
    public var completedAt: Date?
    public var courseId: String?
    public var gradeItemId: String?
    public var priority: Int
    public var category: String
    public var source: String
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, title: String, notes: String?, dueAt: Date?,
                completedAt: Date?, courseId: String?, gradeItemId: String?,
                priority: Int, category: String, source: String,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.courseId = courseId
        self.gradeItemId = gradeItemId
        self.priority = priority
        self.category = category
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, priority, category, source
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case courseId = "course_id"
        case gradeItemId = "grade_item_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
