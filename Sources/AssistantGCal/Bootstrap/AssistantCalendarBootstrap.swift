import Foundation
import AssistantStore

public final class AssistantCalendarBootstrap {

    public static let summary = "Assistant"
    public static let settingKey = "gcal_assistant_calendar_id"

    private let client: GCalClient
    private let setting: SettingRepository

    public init(client: GCalClient, db: AssistantDB) {
        self.client = client
        self.setting = SettingRepository(db: db)
    }

    public func cachedCalendarId() throws -> String? {
        try setting.get(Self.settingKey)
    }

    public func ensureAssistantCalendar() async throws -> String {
        if let cached = try cachedCalendarId() { return cached }

        let list = try await client.listCalendars()
        if let existing = list.items.first(where: { $0.summary == Self.summary }) {
            try setting.set(Self.settingKey, value: existing.id)
            return existing.id
        }

        let created = try await client.createCalendar(summary: Self.summary)
        try setting.set(Self.settingKey, value: created.id)
        return created.id
    }
}
