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

    public init(frequency: Frequency, interval: Int, byWeekday: [Int],
                untilDate: Date?, count: Int?) {
        self.frequency = frequency
        self.interval = interval
        self.byWeekday = byWeekday
        self.untilDate = untilDate
        self.count = count
    }

    /// Maps a `Calendar` weekday (1 = Sun … 7 = Sat) to its RRULE token.
    private static let weekdayTokens: [Int: String] = [
        1: "SU", 2: "MO", 3: "TU", 4: "WE", 5: "TH", 6: "FR", 7: "SA"
    ]

    /// End-of-day, UTC, in RRULE UNTIL form (`yyyyMMdd'T'235959'Z'`).
    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'235959'Z'"
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
            parts.append("UNTIL=\(Self.untilFormatter.string(from: until))")
        } else if let count = count {
            parts.append("COUNT=\(count)")
        }
        return "RRULE:" + parts.joined(separator: ";")
    }
}
