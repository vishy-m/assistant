import Foundation
import GRDB

public struct ClassPin: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "class_pin"

    public var id: String
    public var courseId: String
    public var fileId: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var zOrder: Int
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, courseId: String, fileId: String, x: Double, y: Double,
                width: Double, height: Double, rotation: Double = 0, zOrder: Int = 0,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.courseId = courseId; self.fileId = fileId
        self.x = x; self.y = y; self.width = width; self.height = height
        self.rotation = rotation; self.zOrder = zOrder
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, x, y, width, height, rotation
        case courseId = "course_id"
        case fileId = "file_id"
        case zOrder = "z_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
