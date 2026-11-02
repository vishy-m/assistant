import XCTest
@testable import AssistantShared

final class WeekGridLayoutTests: XCTestCase {

    private let layout = WeekGridLayout(hourHeight: 60, dayStartHour: 0)

    private var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }

    private var chicago: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// Wall time in America/Chicago. A missing spring-forward hour resolves to
    /// the next valid instant, matching `Calendar.date(from:)`.
    private func chicagoDate(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.calendar = chicago
        comps.timeZone = chicago.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return chicago.date(from: comps)!
    }

    func testTimeToOffset() {
        let base = Date(timeIntervalSince1970: 0)
        let twoThirty = base.addingTimeInterval(2.5 * 3600)
        XCTAssertEqual(layout.yOffset(for: twoThirty, dayStart: base, calendar: gmt),
                       150, accuracy: 0.001)
    }

    func testOffsetToSnappedTime() {
        let base = Date(timeIntervalSince1970: 0)
        let snapped = layout.time(forYOffset: 70, dayStart: base, calendar: gmt)
        XCTAssertEqual(snapped.timeIntervalSince(base), 75 * 60, accuracy: 0.001)
    }

    func testOffsetRespectsDayStartHourOnGMT() {
        let shifted = WeekGridLayout(hourHeight: 60, dayStartHour: 8)
        let base = Date(timeIntervalSince1970: 0)
        let tenThirty = base.addingTimeInterval(10.5 * 3600)
        XCTAssertEqual(shifted.yOffset(for: tenThirty, dayStart: base, calendar: gmt),
                       150, accuracy: 0.001)
    }

    /// 09:00 stays on the 09:00 row on both 2026 DST transitions, and clicking
    /// that row creates hour 9. Elapsed seconds put spring 09:00 on the 08:00
    /// row and fall 09:00 on the 10:00 row.
    func testDSTNineAMMatchesNormalDayAndCreatesThatHour() {
        let normal = chicagoDate(2026, 6, 15, 9, 0)
        let normalY = layout.yOffset(for: normal,
                                     dayStart: chicago.startOfDay(for: normal),
                                     calendar: chicago)
        XCTAssertEqual(normalY, 9 * layout.hourHeight, accuracy: 0.001)

        for (month, day) in [(3, 8), (11, 1)] {
            let date = chicagoDate(2026, month, day, 9, 0)
            let dayStart = chicago.startOfDay(for: date)
            let y = layout.yOffset(for: date, dayStart: dayStart, calendar: chicago)
            XCTAssertEqual(y, normalY, accuracy: 0.001,
                           "\(month)/\(day) 09:00 should sit on the 09:00 row")
            let created = layout.time(forYOffset: normalY, dayStart: dayStart, calendar: chicago)
            XCTAssertEqual(chicago.component(.hour, from: created), 9,
                           "\(month)/\(day) 09:00 row should create hour 9")
            XCTAssertEqual(chicago.component(.minute, from: created), 0)
            XCTAssertEqual(chicago.component(.day, from: created), day)
        }
    }

    /// The repeated 01:30 on the fall-back day shares one wall-clock row.
    /// Reverse mapping uses Calendar's first occurrence.
    func testFallRepeatedHourSharesOneRowAndResolvesToFirstOccurrence() {
        let first = chicagoDate(2026, 11, 1, 1, 30)
        let second = first.addingTimeInterval(3600)
        let dayStart = chicago.startOfDay(for: first)
        let y1 = layout.yOffset(for: first, dayStart: dayStart, calendar: chicago)
        let y2 = layout.yOffset(for: second, dayStart: dayStart, calendar: chicago)
        XCTAssertEqual(y1, 1.5 * layout.hourHeight, accuracy: 0.001)
        XCTAssertEqual(y1, y2, accuracy: 0.001)
        let created = layout.time(forYOffset: y1, dayStart: dayStart, calendar: chicago)
        XCTAssertEqual(created, first)
    }

    /// 02:00 does not exist on the spring-forward day. The 02:00 row resolves
    /// to 03:00, the next valid instant.
    func testSpringMissingHourResolvesToNextValidInstant() {
        let dayStart = chicago.startOfDay(for: chicagoDate(2026, 3, 8, 9, 0))
        let created = layout.time(forYOffset: 2 * layout.hourHeight,
                                  dayStart: dayStart, calendar: chicago)
        XCTAssertEqual(chicago.component(.hour, from: created), 3)
        XCTAssertEqual(chicago.component(.minute, from: created), 0)
        XCTAssertEqual(created, chicagoDate(2026, 3, 8, 3, 0))
    }

    func testWallHourIgnoresDSTElapsedShift() {
        XCTAssertEqual(WeekGridLayout.wallHour(of: chicagoDate(2026, 11, 1, 9, 0),
                                               calendar: chicago), 9)
        XCTAssertEqual(WeekGridLayout.wallHour(of: chicagoDate(2026, 3, 8, 9, 0),
                                               calendar: chicago), 9)
        XCTAssertEqual(WeekGridLayout.wallHour(of: chicagoDate(2026, 6, 15, 9, 0),
                                               calendar: chicago), 9)
    }

    func testExclusiveEndHourUsesWallClock() {
        let fallStart = chicago.startOfDay(for: chicagoDate(2026, 11, 1, 9, 0))
        XCTAssertEqual(
            WeekGridLayout.exclusiveEndHour(of: chicagoDate(2026, 11, 1, 10, 30),
                                            dayStart: fallStart, calendar: chicago),
            11)
        XCTAssertEqual(
            WeekGridLayout.exclusiveEndHour(of: chicagoDate(2026, 11, 1, 10, 0),
                                            dayStart: fallStart, calendar: chicago),
            10)
        let nextMidnight = chicago.date(byAdding: .day, value: 1, to: fallStart)!
        XCTAssertEqual(
            WeekGridLayout.exclusiveEndHour(of: nextMidnight,
                                            dayStart: fallStart, calendar: chicago),
            24)

        let springStart = chicago.startOfDay(for: chicagoDate(2026, 3, 8, 9, 0))
        XCTAssertEqual(
            WeekGridLayout.exclusiveEndHour(of: chicagoDate(2026, 3, 8, 10, 30),
                                            dayStart: springStart, calendar: chicago),
            11)
    }

    func testEventBlockHeight() {
        XCTAssertEqual(layout.height(forDurationSeconds: 3600), 60, accuracy: 0.001)
        XCTAssertEqual(layout.height(forDurationSeconds: 900), 15, accuracy: 0.001)
    }

    func testNonOverlappingEventsEachGetFullWidth() {
        let base = Date(timeIntervalSince1970: 0)
        let cols = WeekGridLayout.columns(for: [
            .init(id: "a", start: base, end: base.addingTimeInterval(3600)),
            .init(id: "b", start: base.addingTimeInterval(7200),
                           end: base.addingTimeInterval(10800))
        ])
        XCTAssertEqual(cols["a"]?.columnCount, 1)
        XCTAssertEqual(cols["b"]?.columnCount, 1)
    }

    func testOverlappingEventsSplitIntoColumns() {
        let base = Date(timeIntervalSince1970: 0)
        let cols = WeekGridLayout.columns(for: [
            .init(id: "a", start: base, end: base.addingTimeInterval(3600)),
            .init(id: "b", start: base.addingTimeInterval(1800),
                           end: base.addingTimeInterval(5400))
        ])
        XCTAssertEqual(cols["a"]?.columnCount, 2)
        XCTAssertEqual(cols["b"]?.columnCount, 2)
        XCTAssertNotEqual(cols["a"]?.columnIndex, cols["b"]?.columnIndex)
    }
}
