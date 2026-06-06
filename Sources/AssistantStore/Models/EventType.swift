import Foundation
import GRDB

public struct EventType: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "event_type"

    public var id: String
    public var name: String
    public var colorHex: String
    public var googleColorId: String
    public var symbolName: String?
    public var isBuiltin: Bool
    public var sortOrder: Int

    public init(id: String, name: String, colorHex: String, googleColorId: String,
                symbolName: String?, isBuiltin: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.googleColorId = googleColorId
        self.symbolName = symbolName
        self.isBuiltin = isBuiltin
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case googleColorId = "google_color_id"
        case symbolName = "symbol_name"
        case isBuiltin = "is_builtin"
        case sortOrder = "sort_order"
    }
}
