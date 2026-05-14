import Foundation
import GRDB

public struct Setting: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "setting"

    public let key: String
    public let valueJson: Data
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case key
        case valueJson = "value_json"
        case updatedAt = "updated_at"
    }
}
