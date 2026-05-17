import Foundation

public struct GCalCalendarList: Codable, Equatable {
    public let items: [Item]
    public struct Item: Codable, Equatable {
        public let id: String
        public let summary: String
        public let primary: Bool?
        public let accessRole: String?
    }
}

public struct GCalTime: Codable, Equatable {
    public let dateTime: Date?
    public let date: String?            // all-day events use this instead
    public let timeZone: String?
}

public struct GCalEvent: Codable, Equatable {
    public let id: String
    public let summary: String?
    public let description: String?
    public let start: GCalTime?
    public let end: GCalTime?
    public let location: String?
    public let status: String?          // "confirmed", "tentative", "cancelled"
}

public struct GCalEventList: Codable, Equatable {
    public let items: [GCalEvent]
    public let nextPageToken: String?
    public let nextSyncToken: String?
}

public struct GCalCalendarCreateBody: Codable {
    public let summary: String
    public let timeZone: String?
    public init(summary: String, timeZone: String? = nil) {
        self.summary = summary
        self.timeZone = timeZone
    }
}
