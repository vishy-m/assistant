import XCTest
@testable import AssistantBriefings

final class ScheduleCalendarTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    func testNextFireToday() throws {
        // Current time 06:00, target 08:00 → today at 08:00
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 6, minute: 0)
        let next = ScheduleCalendar.nextFire(after: now, hour: 8, minute: 0)
        XCTAssertEqual(cal.component(.hour, from: next), 8)
        XCTAssertEqual(cal.component(.day, from: next), 13)
    }

    func testNextFireRollsToTomorrow() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 9, minute: 0)
        let next = ScheduleCalendar.nextFire(after: now, hour: 8, minute: 0)
        XCTAssertEqual(cal.component(.day, from: next), 14)
    }

    func testNextFireExactlyAtTarget() throws {
        // If we're exactly at target, we should fire today still (don't roll past 0s)
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 8, minute: 0)
        let next = ScheduleCalendar.nextFire(after: now, hour: 8, minute: 0, includeNow: true)
        XCTAssertEqual(cal.component(.day, from: next), 13)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return cal.date(from: comps)!
    }
}
