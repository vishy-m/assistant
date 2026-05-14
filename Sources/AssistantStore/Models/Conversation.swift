import Foundation
import GRDB

public struct Conversation: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "conversation"

    public var id: String
    public var startedAt: Date
    public var lastActiveAt: Date
    public var summary: String?

    public init(id: String, startedAt: Date = Date(), lastActiveAt: Date = Date(),
                summary: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case id, summary
        case startedAt = "started_at"
        case lastActiveAt = "last_active_at"
    }
}
