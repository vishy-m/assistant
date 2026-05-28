import Foundation
import GRDB

public struct GCalEventCache: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "gcal_event_cache"

    public var gcalEventId: String
    public var calendarId: String
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var location: String?
    public var category: String
    public var lastSyncedAt: Date
    public var rawJson: String
    public var recurringEventId: String?

    public init(gcalEventId: String, calendarId: String, title: String,
                startAt: Date, endAt: Date, location: String?, category: String,
                lastSyncedAt: Date, rawJson: String, recurringEventId: String? = nil) {
        self.gcalEventId = gcalEventId
        self.calendarId = calendarId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.location = location
        self.category = category
        self.lastSyncedAt = lastSyncedAt
        self.rawJson = rawJson
        self.recurringEventId = recurringEventId
    }

    enum CodingKeys: String, CodingKey {
        case title, location, category
        case gcalEventId = "gcal_event_id"
        case calendarId = "calendar_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case lastSyncedAt = "last_synced_at"
        case rawJson = "raw_json"
        case recurringEventId = "recurring_event_id"
    }
}
