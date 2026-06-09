import XCTest
@testable import AssistantShared

final class RecurrenceRuleTests: XCTestCase {

    func testDailyIntervalOneOmitsInterval() {
        let r = RecurrenceRule(frequency: .daily, interval: 1,
                               byWeekday: [], untilDate: nil, count: nil)
        XCTAssertEqual(r.rruleString, "RRULE:FREQ=DAILY")
    }

    func testWeeklyWithIntervalAndDays() {
        // weekday ints: 1=Sun ... 7=Sat → 2=Mon, 4=Wed
        let r = RecurrenceRule(frequency: .weekly, interval: 2,
                               byWeekday: [4, 2], untilDate: nil, count: nil)
        XCTAssertEqual(r.rruleString, "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE")
    }

    func testCountEndProducesCount() {
        let r = RecurrenceRule(frequency: .daily, interval: 1,
                               byWeekday: [], untilDate: nil, count: 5)
        XCTAssertEqual(r.rruleString, "RRULE:FREQ=DAILY;COUNT=5")
    }

    func testUntilEndProducesUTCUntil() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 12; comps.day = 31
        comps.timeZone = TimeZone(identifier: "America/Chicago")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let r = RecurrenceRule(frequency: .monthly, interval: 1,
                               byWeekday: [], untilDate: date, count: nil)
        // UNTIL is end-of-day in UTC for the chosen calendar date.
        XCTAssertEqual(r.rruleString, "RRULE:FREQ=MONTHLY;UNTIL=20261231T235959Z")
    }

    func testUntilTakesPrecedenceOverCount() {
        var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = 1
        comps.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let r = RecurrenceRule(frequency: .daily, interval: 3,
                               byWeekday: [], untilDate: date, count: 9)
        XCTAssertTrue(r.rruleString.contains("UNTIL=20260101T235959Z"))
        XCTAssertFalse(r.rruleString.contains("COUNT"))
    }

    func testByWeekdayIgnoredWhenNotWeekly() {
        let r = RecurrenceRule(frequency: .daily, interval: 1,
                               byWeekday: [2, 4], untilDate: nil, count: nil)
        XCTAssertEqual(r.rruleString, "RRULE:FREQ=DAILY")
    }

    func testCodableRoundTrip() throws {
        let r = RecurrenceRule(frequency: .weekly, interval: 2,
                               byWeekday: [2, 4, 6],
                               untilDate: Date(timeIntervalSince1970: 1_700_000_000),
                               count: nil)
        let decoded = try JSONDecoder().decode(
            RecurrenceRule.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded, r)
    }
}
