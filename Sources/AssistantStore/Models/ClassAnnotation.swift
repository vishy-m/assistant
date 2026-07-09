import Foundation
import GRDB

public struct ClassAnnotation: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "class_annotation"

    public var id: String
    public var courseId: String
    public var kind: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var zOrder: Int
    public var payload: String
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, courseId: String, kind: String, x: Double, y: Double,
                width: Double, height: Double, zOrder: Int = 0, payload: String,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.courseId = courseId; self.kind = kind
        self.x = x; self.y = y; self.width = width; self.height = height
        self.zOrder = zOrder; self.payload = payload
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, x, y, width, height, payload
        case courseId = "course_id"
        case zOrder = "z_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
