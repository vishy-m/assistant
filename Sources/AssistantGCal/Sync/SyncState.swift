import Foundation
import AssistantStore

public struct SyncState {
    private let setting: SettingRepository

    public init(db: AssistantDB) { self.setting = SettingRepository(db: db) }

    private struct Tokens: Codable { var byCalendarId: [String: String] }
    private static let key = "gcal_sync_tokens"

    private func load() throws -> Tokens {
        (try setting.getCodable(Self.key)) ?? Tokens(byCalendarId: [:])
    }
    private func save(_ t: Tokens) throws {
        try setting.setCodable(Self.key, value: t)
    }

    public func syncToken(for calendarId: String) throws -> String? {
        try load().byCalendarId[calendarId]
    }

    public func setSyncToken(_ calendarId: String, token: String) throws {
        var t = try load()
        t.byCalendarId[calendarId] = token
        try save(t)
    }

    public func clearSyncToken(_ calendarId: String) throws {
        var t = try load()
        t.byCalendarId.removeValue(forKey: calendarId)
        try save(t)
    }
}
