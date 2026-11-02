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

    // Coverage horizon: how far ahead each calendar's cache has been filled.
    // A sync token only reports changes, so events that were beyond the first
    // window and never edited must be fetched by an explicit gap fill.

    private struct Coverage: Codable { var endByCalendarId: [String: Double] }
    private static let coverageKey = "gcal_coverage_end"

    public func coverageEnd(for calendarId: String) throws -> Date? {
        let c: Coverage? = try setting.getCodable(Self.coverageKey)
        return c?.endByCalendarId[calendarId].map(Date.init(timeIntervalSince1970:))
    }

    public func setCoverageEnd(_ calendarId: String, end: Date) throws {
        var c: Coverage = (try setting.getCodable(Self.coverageKey)) ?? Coverage(endByCalendarId: [:])
        c.endByCalendarId[calendarId] = end.timeIntervalSince1970
        try setting.setCodable(Self.coverageKey, value: c)
    }
}
