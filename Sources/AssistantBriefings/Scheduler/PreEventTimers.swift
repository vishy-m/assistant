import Foundation
import AssistantStore

public actor PreEventTimers {

    private var fired: Set<String> = []   // gcal_event_id + lead-time tag
    private let leadTimesByCategory: [String: [Int]]

    public init(leadTimesByCategory: [String: [Int]] = PreEventTimers.defaultLeadTimes()) {
        self.leadTimesByCategory = leadTimesByCategory
    }

    public static func defaultLeadTimes() -> [String: [Int]] {
        [
            "exam":                  [24 * 60, 60],
            "assignment_due":        [12 * 60, 60],
            "class":                 [10],
            "club_meeting":          [30],
            "internship_deadline":   [72 * 60, 24 * 60, 60],
            "generic":               [15]
        ]
    }

    public struct Fire: Equatable {
        public let eventId: String
        public let leadMinutes: Int
        public let fireAt: Date
        public let title: String
        public let category: String
    }

    /// Compute upcoming fires within `window` from `now`. Returns sorted by fireAt.
    public func upcomingFires(events: [GCalEventCache], now: Date, window: TimeInterval) -> [Fire] {
        var fires: [Fire] = []
        for e in events {
            let leads = leadTimesByCategory[e.category] ?? leadTimesByCategory["generic"] ?? [15]
            for lead in leads {
                let fireAt = e.startAt.addingTimeInterval(-Double(lead) * 60)
                guard fireAt > now, fireAt < now.addingTimeInterval(window) else { continue }
                let key = "\(e.gcalEventId)#\(lead)"
                if fired.contains(key) { continue }
                fires.append(Fire(eventId: e.gcalEventId, leadMinutes: lead,
                                  fireAt: fireAt, title: e.title, category: e.category))
            }
        }
        return fires.sorted { $0.fireAt < $1.fireAt }
    }

    public func markFired(eventId: String, leadMinutes: Int) {
        fired.insert("\(eventId)#\(leadMinutes)")
    }
}
