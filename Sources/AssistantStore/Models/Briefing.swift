import Foundation
import GRDB

public struct Briefing: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "briefing_log"

    public var id: String
    public var kind: String
    public var firedAt: Date
    public var payloadJson: String
    public var dismissedAt: Date?
    public var actedOn: Bool

    public init(id: String, kind: String, firedAt: Date, payloadJson: String,
                dismissedAt: Date?, actedOn: Bool) {
        self.id = id
        self.kind = kind
        self.firedAt = firedAt
        self.payloadJson = payloadJson
        self.dismissedAt = dismissedAt
        self.actedOn = actedOn
    }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case firedAt = "fired_at"
        case payloadJson = "payload_json"
        case dismissedAt = "dismissed_at"
        case actedOn = "acted_on"
    }
}
