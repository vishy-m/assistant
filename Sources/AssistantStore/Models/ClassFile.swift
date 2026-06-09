import Foundation
import GRDB

public struct ClassFile: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "class_file"

    public var id: String
    public var courseId: String
    public var folderId: String?
    public var name: String
    public var storedName: String
    public var contentType: String
    public var byteSize: Int
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, courseId: String, folderId: String?, name: String,
                storedName: String, contentType: String, byteSize: Int,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.courseId = courseId; self.folderId = folderId
        self.name = name; self.storedName = storedName; self.contentType = contentType
        self.byteSize = byteSize; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case courseId = "course_id"
        case folderId = "folder_id"
        case storedName = "stored_name"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
