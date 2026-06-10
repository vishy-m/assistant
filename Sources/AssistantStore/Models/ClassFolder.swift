import Foundation
import GRDB

public struct ClassFolder: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "class_folder"

    public var id: String
    public var courseId: String
    public var parentFolderId: String?
    public var name: String
    public var sortOrder: Int
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, courseId: String, parentFolderId: String?, name: String,
                sortOrder: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.courseId = courseId; self.parentFolderId = parentFolderId
        self.name = name; self.sortOrder = sortOrder
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case courseId = "course_id"
        case parentFolderId = "parent_folder_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
