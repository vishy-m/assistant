import Foundation
import GRDB

public struct PendingGCalOp: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pending_gcal_op"

    public var id: String
    public var opType: String
    public var payloadJson: String
    public var attempts: Int
    public var lastAttemptAt: Date?
    public var createdAt: Date

    public init(id: String, opType: String, payloadJson: String,
                attempts: Int, lastAttemptAt: Date?, createdAt: Date) {
        self.id = id
        self.opType = opType
        self.payloadJson = payloadJson
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, attempts
        case opType = "op_type"
        case payloadJson = "payload_json"
        case lastAttemptAt = "last_attempt_at"
        case createdAt = "created_at"
    }
}
