import Foundation
import GRDB

public struct SettingRepository {
    private let db: AssistantDB

    public init(db: AssistantDB) {
        self.db = db
    }

    /// Set a string-valued setting.
    public func set(_ key: String, value: String) throws {
        try setCodable(key, value: value)
    }

    /// Read a string-valued setting.
    public func get(_ key: String) throws -> String? {
        try getCodable(key)
    }

    /// Set any Codable value (stored as JSON in value_json).
    public func setCodable<T: Encodable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        try db.queue.write { db in
            try db.execute(sql: """
                INSERT INTO setting (key, value_json, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at
            """, arguments: [key, data, Date()])
        }
    }

    /// Read the raw stored JSON for a key, bypassing struct decoding.
    /// Used by migrations that need fields no longer present in the model.
    public func rawData(_ key: String) throws -> Data? {
        try db.queue.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value_json FROM setting WHERE key = ?",
                arguments: [key])
        }
    }

    /// Read any Codable value.
    public func getCodable<T: Decodable>(_ key: String) throws -> T? {
        try db.queue.read { db in
            guard let data: Data = try Data.fetchOne(
                db,
                sql: "SELECT value_json FROM setting WHERE key = ?",
                arguments: [key]
            ) else {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
}
