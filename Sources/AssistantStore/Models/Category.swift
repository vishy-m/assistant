import Foundation
import GRDB

public struct Category: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "category"

    public var name: String
    public var colorHex: String
    public var isDefault: Bool

    public init(name: String, colorHex: String, isDefault: Bool = false) {
        self.name = name
        self.colorHex = colorHex
        self.isDefault = isDefault
    }

    enum CodingKeys: String, CodingKey {
        case name
        case colorHex = "color_hex"
        case isDefault = "is_default"
    }
}
