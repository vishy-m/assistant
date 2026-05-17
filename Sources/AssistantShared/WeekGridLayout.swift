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

    /// Vertical offset, in points, of `date` measured from the top of its day.
    public func yOffset(for date: Date, dayStart: Date) -> Double {
        let secondsFromDayStart = date.timeIntervalSince(dayStart)
            - Double(dayStartHour) * 3600
        return secondsFromDayStart / 3600 * hourHeight
    }

    /// Time corresponding to a vertical offset, snapped to `snapMinutes`.
    public func time(forYOffset y: Double, dayStart: Date) -> Date {
        let rawSeconds = y / hourHeight * 3600 + Double(dayStartHour) * 3600
        let snap = Double(snapMinutes) * 60
        let snapped = (rawSeconds / snap).rounded() * snap
        return dayStart.addingTimeInterval(snapped)
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
