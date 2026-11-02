import Foundation
import AssistantShared
import AssistantStore

public actor PreEventTimers {

    private var fired: Set<String> = []   // gcal_event_id + lead-time tag
    private var leadTimesByCategory: [String: [Int]]

    /// A missed fire is still delivered inside this window, and only while the event has not started.
    private static let catchUpWindow: TimeInterval = 30 * 60

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

    /// Saved settings, with an empty array replaced by that category's default.
    public static func leadTimes(from settings: AppSettings) -> [String: [Int]] {
        let saved = settings.leadTimes
        let defaults = defaultLeadTimes()
        func pick(_ value: [Int], key: String) -> [Int] {
            value.isEmpty ? (defaults[key] ?? [15]) : value
        }
        return [
            "exam": pick(saved.exam, key: "exam"),
            "assignment_due": pick(saved.assignmentDue, key: "assignment_due"),
            "class": pick(saved.classCategory, key: "class"),
            "club_meeting": pick(saved.clubMeeting, key: "club_meeting"),
            "internship_deadline": pick(saved.internshipDeadline, key: "internship_deadline"),
            "generic": pick(saved.generic, key: "generic")
        ]
    }

    /// Civil days from the start of `now` through the longest lead (at least 24h) plus one day.
    /// Day adds stay on the calendar so a DST spring-forward does not skip a date.
    public static func queryDates(now: Date,
                                  leadMinutes: [Int],
                                  calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        let maxLeadMinutes = max(leadMinutes.max() ?? 0, 24 * 60)
        let reach = now.addingTimeInterval(TimeInterval(maxLeadMinutes) * 60)
        guard let horizon = calendar.date(byAdding: .day, value: 1, to: reach) else {
            return [calendar.startOfDay(for: now)]
        }
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: now)
        let last = calendar.startOfDay(for: horizon)
        while cursor <= last {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return dates
    }

    public struct Fire: Equatable {
        public let eventId: String
        public let leadMinutes: Int
        public let fireAt: Date
        public let title: String
        public let category: String
    }

    /// Leads for one event. `eventType` wins for `exam` and `class`. Internship applies only
    /// when the event type or category is that key. Anything else uses the generic list.
    public func leads(for event: GCalEventCache) -> [Int] {
        let key = Self.leadKey(eventType: event.eventType, category: event.category)
        if let leads = leadTimesByCategory[key], !leads.isEmpty { return leads }
        if let generic = leadTimesByCategory["generic"], !generic.isEmpty { return generic }
        return Self.defaultLeadTimes()[key] ?? [15]
    }

    /// Compute upcoming fires within `window` from `now`, plus a 30-minute catch-up.
    /// Returns sorted by fireAt. Pass `leadTimes` to apply a settings reload for this pass.
    public func upcomingFires(events: [GCalEventCache], now: Date, window: TimeInterval,
                              leadTimes: [String: [Int]]? = nil) -> [Fire] {
        if let leadTimes {
            leadTimesByCategory = leadTimes
        }
        var fires: [Fire] = []
        for e in events {
            let leads = leads(for: e)
            for lead in leads {
                let fireAt = e.startAt.addingTimeInterval(-Double(lead) * 60)
                let upcoming = fireAt > now && fireAt < now.addingTimeInterval(window)
                let catchUp = fireAt <= now
                    && now.timeIntervalSince(fireAt) <= Self.catchUpWindow
                    && now < e.startAt
                guard upcoming || catchUp else { continue }
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

    static func leadKey(eventType: String?, category: String) -> String {
        if let type = normalized(eventType) {
            switch type {
            case "exam": return "exam"
            case "class": return "class"
            case "internship_deadline": return "internship_deadline"
            default: break
            }
        }
        switch normalized(category) ?? "" {
        case "exam": return "exam"
        case "assignment", "assignment_due", "assignmentdue": return "assignment_due"
        case "class": return "class"
        case "club", "club_meeting", "clubmeeting": return "club_meeting"
        case "internship_deadline", "internshipdeadline": return "internship_deadline"
        default: return "generic"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
