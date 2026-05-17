import Foundation
import AssistantStore

public final class AssistantCalendarBootstrap {

    public static let summary = "Assistant"
    public static let settingKey = "gcal_assistant_calendar_id"
    public static let timeZoneKey = "gcal_assistant_calendar_timezone"

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
        let localTZ = TimeZone.current.identifier
        let calID: String

        if let cached = try cachedCalendarId() {
            calID = cached
        } else {
            let list = try await client.listCalendars()
            if let existing = list.items.first(where: { $0.summary == Self.summary }) {
                calID = existing.id
            } else {
                calID = try await client.createCalendar(
                    summary: Self.summary, timeZone: localTZ).id
            }
            try setting.set(Self.settingKey, value: calID)
        }

        // Keep the calendar's display zone aligned with the user's. A calendar
        // created without a `timeZone` defaults to UTC; this corrects that and
        // also follows the user if they travel. Non-fatal — a transient
        // failure simply retries on the next event.
        if (try? setting.get(Self.timeZoneKey)) != localTZ {
            do {
                try await client.updateCalendarTimeZone(id: calID, timeZone: localTZ)
                try setting.set(Self.timeZoneKey, value: localTZ)
            } catch { /* retried on the next event */ }
        }
        return calID
    }
}
