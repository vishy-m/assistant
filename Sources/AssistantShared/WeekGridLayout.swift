import Foundation

/// Pure geometry for the week time-grid: time ↔ vertical offset, event block
/// sizing, and splitting overlapping events into side-by-side columns.
public struct WeekGridLayout {

    public let hourHeight: Double
    public let dayStartHour: Int
    public let snapMinutes: Int

    public init(hourHeight: Double, dayStartHour: Int, snapMinutes: Int = 15) {
        self.hourHeight = hourHeight
        self.dayStartHour = dayStartHour
        self.snapMinutes = snapMinutes
    }

    /// Wall-clock offset of `date` below `dayStartHour`, in points. One row per
    /// local hour, so a DST shift does not move 09:00 onto another row.
    public func yOffset(for date: Date, dayStart: Date, calendar: Calendar = .current) -> Double {
        let hours = Self.wallHours(of: date, calendar: calendar) - Double(dayStartHour)
        return hours * hourHeight
    }

    /// Wall time on `dayStart`'s civil day for a vertical offset, snapped to
    /// `snapMinutes`. A missing spring-forward hour resolves to the next valid
    /// instant (02:00 → 03:00). A repeated fall-back hour uses Calendar's
    /// first occurrence.
    public func time(forYOffset y: Double, dayStart: Date, calendar: Calendar = .current) -> Date {
        let rawSeconds = y / hourHeight * 3600 + Double(dayStartHour) * 3600
        let snap = Double(snapMinutes) * 60
        let snapped = (rawSeconds / snap).rounded() * snap
        let whole = max(0, Int(snapped.rounded()))
        let ymd = calendar.dateComponents([.year, .month, .day], from: dayStart)
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = ymd.year
        comps.month = ymd.month
        comps.day = ymd.day
        comps.hour = whole / 3600
        comps.minute = (whole % 3600) / 60
        comps.second = whole % 60
        return calendar.date(from: comps) ?? dayStart
    }

    /// Wall-clock hour (0...23) of `date` in `calendar`.
    public static func wallHour(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date)
    }

    /// Exclusive end row for an event that began on `dayStart`'s civil day.
    /// 10:00 → 10, 10:30 → 11. An end on a later civil day → 24.
    public static func exclusiveEndHour(of end: Date, dayStart: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: dayStart)
        let endDay = calendar.startOfDay(for: end)
        if endDay > startDay { return 24 }
        if endDay < startDay { return 0 }
        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: end)
        let hour = comps.hour ?? 0
        if (comps.minute ?? 0) > 0 || (comps.second ?? 0) > 0 || (comps.nanosecond ?? 0) > 0 {
            return min(24, hour + 1)
        }
        return hour
    }

    private static func wallHours(of date: Date, calendar: Calendar) -> Double {
        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hour = Double(comps.hour ?? 0)
        let minute = Double(comps.minute ?? 0)
        let second = Double(comps.second ?? 0)
        let fraction = Double(comps.nanosecond ?? 0) / 1_000_000_000
        return hour + minute / 60 + (second + fraction) / 3600
    }

    public func height(forDurationSeconds seconds: Double) -> Double {
        max(seconds / 3600 * hourHeight, 1)
    }

    // MARK: - Overlap columns

    public struct Interval {
        public let id: String
        public let start: Date
        public let end: Date
        public init(id: String, start: Date, end: Date) {
            self.id = id; self.start = start; self.end = end
        }
    }

    public struct Placement: Equatable {
        public let columnIndex: Int
        public let columnCount: Int
        public init(columnIndex: Int, columnCount: Int) {
            self.columnIndex = columnIndex
            self.columnCount = columnCount
        }
    }

    /// Assigns each interval a column index and the column count of its
    /// overlap cluster, so blocks in the same time range render side by side.
    public static func columns(for intervals: [Interval]) -> [String: Placement] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [String: Placement] = [:]
        var cluster: [Interval] = []
        var columnOf: [String: Int] = [:]

        func flush() {
            guard !cluster.isEmpty else { return }
            let count = (columnOf.values.max() ?? 0) + 1
            for iv in cluster {
                result[iv.id] = Placement(columnIndex: columnOf[iv.id] ?? 0,
                                          columnCount: count)
            }
            cluster.removeAll()
            columnOf.removeAll()
        }

        var clusterEnd: Date?
        for iv in sorted {
            if let end = clusterEnd, iv.start >= end {
                flush()
                clusterEnd = nil
            }
            var used = Set<Int>()
            for existing in cluster where existing.end > iv.start {
                if let c = columnOf[existing.id] { used.insert(c) }
            }
            var col = 0
            while used.contains(col) { col += 1 }
            columnOf[iv.id] = col
            cluster.append(iv)
            clusterEnd = max(clusterEnd ?? iv.end, iv.end)
        }
        flush()
        return result
    }
}
