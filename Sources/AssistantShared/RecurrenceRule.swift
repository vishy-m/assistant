import Foundation

/// A customizable recurrence, serialized to an iCal RRULE string for Google
/// Calendar. `byWeekday` uses `Calendar` weekday integers (1 = Sunday … 7 =
/// Saturday) and only applies when `frequency == .weekly`. The end is "never"
/// when both `untilDate` and `count` are nil; `untilDate` takes precedence if
/// both are set.
public struct RecurrenceRule: Codable, Equatable {

    public enum Frequency: String, Codable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    public var byWeekday: [Int]
    public var untilDate: Date?
    public var count: Int?
    /// IANA zone for the "ends on date" civil day. Nil means `TimeZone.current`
    /// at the moment `rruleString` is built.
    public var timeZoneID: String?

    public init(frequency: Frequency, interval: Int, byWeekday: [Int],
                untilDate: Date?, count: Int?, timeZoneID: String? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.byWeekday = byWeekday
        self.untilDate = untilDate
        self.count = count
        self.timeZoneID = timeZoneID
    }

    /// Maps a `Calendar` weekday (1 = Sun … 7 = Sat) to its RRULE token.
    private static let weekdayTokens: [Int: String] = [
        1: "SU", 2: "MO", 3: "TU", 4: "WE", 5: "TH", 6: "FR", 7: "SA"
    ]

    /// UTC instant of the local end of the selected civil day (`yyyyMMdd'T'HHmmss'Z'`).
    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    public var rruleString: String {
        var parts = ["FREQ=\(frequency.rawValue.uppercased())"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if frequency == .weekly && !byWeekday.isEmpty {
            let days = byWeekday.sorted().compactMap { Self.weekdayTokens[$0] }
            if !days.isEmpty { parts.append("BYDAY=\(days.joined(separator: ","))") }
        }
        if let until = untilDate {
            parts.append("UNTIL=\(untilStamp(for: until))")
        } else if let count = count {
            parts.append("COUNT=\(count)")
        }
        return "RRULE:" + parts.joined(separator: ";")
    }

    /// 23:59:59 on the civil day of `date` in the series zone, written in UTC.
    /// The date picker's time-of-day is ignored; only its local year/month/day counts.
    private func untilStamp(for date: Date) -> String {
        let zone = Self.zone(for: timeZoneID)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let ymd = calendar.dateComponents([.year, .month, .day], from: date)
        var end = DateComponents()
        end.calendar = calendar
        end.timeZone = zone
        end.year = ymd.year
        end.month = ymd.month
        end.day = ymd.day
        end.hour = 23
        end.minute = 59
        end.second = 59
        let instant = calendar.date(from: end) ?? date
        return Self.untilFormatter.string(from: instant)
    }

    private static func zone(for identifier: String?) -> TimeZone {
        if let identifier, let zone = TimeZone(identifier: identifier) {
            return zone
        }
        return .current
    }
}
