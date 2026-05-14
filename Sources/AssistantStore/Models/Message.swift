import Foundation
import GRDB

public struct Message: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message"

    public var id: String
    public var conversationId: String
    public var role: String
    public var content: String
    public var attachedImagePath: String?
    public var toolCallsJson: String?
    public var modelUsed: String?
    public var createdAt: Date

    public init(id: String, conversationId: String, role: String, content: String,
                attachedImagePath: String?, toolCallsJson: String?,
                modelUsed: String?, createdAt: Date) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.attachedImagePath = attachedImagePath
        self.toolCallsJson = toolCallsJson
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case conversationId = "conversation_id"
        case attachedImagePath = "attached_image_path"
        case toolCallsJson = "tool_calls_json"
        case modelUsed = "model_used"
        case createdAt = "created_at"
    }
}
