import Foundation

public enum ScheduleCalendar {
    public static func nextFire(after now: Date,
                                hour: Int,
                                minute: Int,
                                includeNow: Bool = false,
                                calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let candidate = calendar.date(from: comps) else { return now }
        if candidate > now || (includeNow && candidate == now) { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }
}
