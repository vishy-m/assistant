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

    func testUntilEndIsEndOfLocalCivilDay() {
        // A UTC civil day still ends at 23:59:59Z.
        let utc = civilDate("UTC", 2026, 12, 31)
        let utcRule = RecurrenceRule(frequency: .monthly, interval: 1,
                                     byWeekday: [], untilDate: utc, count: nil,
                                     timeZoneID: "UTC")
        XCTAssertEqual(utcRule.rruleString, "RRULE:FREQ=MONTHLY;UNTIL=20261231T235959Z")

        // Chicago Dec 31 is CST. 23:59:59 local is 05:59:59Z on January 1,
        // so a 20:00 occurrence that day is included.
        let chicago = civilDate("America/Chicago", 2026, 12, 31)
        let chicagoRule = RecurrenceRule(frequency: .monthly, interval: 1,
                                         byWeekday: [], untilDate: chicago, count: nil,
                                         timeZoneID: "America/Chicago")
        XCTAssertEqual(chicagoRule.rruleString, "RRULE:FREQ=MONTHLY;UNTIL=20270101T055959Z")

        // A positive offset must not roll the selected civil day backward.
        let tokyo = civilDate("Asia/Tokyo", 2026, 12, 31)
        let tokyoRule = RecurrenceRule(frequency: .monthly, interval: 1,
                                       byWeekday: [], untilDate: tokyo, count: nil,
                                       timeZoneID: "Asia/Tokyo")
        XCTAssertEqual(tokyoRule.rruleString, "RRULE:FREQ=MONTHLY;UNTIL=20261231T145959Z")
    }

    /// 2026-11-02 is the day after the Chicago fall-back, so the local end is
    /// CST (UTC−6): 23:59:59 is 20261103T055959Z, not the UTC calendar date.
    func testUntilNov2KeepsChicagoAndTokyoCivilDays() {
        let chicago = RecurrenceRule(frequency: .daily, interval: 1, byWeekday: [],
                                     untilDate: civilDate("America/Chicago", 2026, 11, 2),
                                     count: nil, timeZoneID: "America/Chicago")
        XCTAssertEqual(chicago.rruleString, "RRULE:FREQ=DAILY;UNTIL=20261103T055959Z")
        XCTAssertLessThan(civilDate("America/Chicago", 2026, 11, 2, hour: 20),
                          untilInstant(chicago))

        let tokyo = RecurrenceRule(frequency: .daily, interval: 1, byWeekday: [],
                                   untilDate: civilDate("Asia/Tokyo", 2026, 11, 2),
                                   count: nil, timeZoneID: "Asia/Tokyo")
        XCTAssertEqual(tokyo.rruleString, "RRULE:FREQ=DAILY;UNTIL=20261102T145959Z")
    }

    /// 23:59:59 exists on both transition days and is after a 20:00 occurrence.
    func testUntilIncludesEveningOnDSTEndDates() {
        let spring = RecurrenceRule(frequency: .daily, interval: 1, byWeekday: [],
                                    untilDate: civilDate("America/Chicago", 2026, 3, 8),
                                    count: nil, timeZoneID: "America/Chicago")
        XCTAssertEqual(spring.rruleString, "RRULE:FREQ=DAILY;UNTIL=20260309T045959Z")
        XCTAssertLessThan(civilDate("America/Chicago", 2026, 3, 8, hour: 20),
                          untilInstant(spring))

        let fall = RecurrenceRule(frequency: .daily, interval: 1, byWeekday: [],
                                  untilDate: civilDate("America/Chicago", 2026, 11, 1),
                                  count: nil, timeZoneID: "America/Chicago")
        XCTAssertEqual(fall.rruleString, "RRULE:FREQ=DAILY;UNTIL=20261102T055959Z")
        XCTAssertLessThan(civilDate("America/Chicago", 2026, 11, 1, hour: 20),
                          untilInstant(fall))
    }

    func testNilTimeZoneUsesCurrentZoneAtEncodeTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = .current
        comps.year = 2026
        comps.month = 7
        comps.day = 4
        let start = calendar.date(from: comps)!
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        let end = calendar.date(from: comps)!
        let rule = RecurrenceRule(frequency: .daily, interval: 1, byWeekday: [],
                                  untilDate: start, count: nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        XCTAssertEqual(rule.rruleString,
                       "RRULE:FREQ=DAILY;UNTIL=\(formatter.string(from: end))")
    }

    func testUntilTakesPrecedenceOverCount() {
        let date = civilDate("UTC", 2026, 1, 1)
        let r = RecurrenceRule(frequency: .daily, interval: 3,
                               byWeekday: [], untilDate: date, count: 9,
                               timeZoneID: "UTC")
        XCTAssertTrue(r.rruleString.contains("UNTIL=20260101T235959Z"))
        XCTAssertFalse(r.rruleString.contains("COUNT"))
    }

    func testDecodesWithoutTimeZoneID() throws {
        let json = """
        {"frequency":"weekly","interval":2,"byWeekday":[2],"count":4}
        """.data(using: .utf8)!
        let rule = try JSONDecoder().decode(RecurrenceRule.self, from: json)
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.byWeekday, [2])
        XCTAssertNil(rule.timeZoneID)
        XCTAssertNil(rule.untilDate)
        XCTAssertEqual(rule.count, 4)
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

    private func civilDate(_ timeZoneID: String, _ year: Int, _ month: Int, _ day: Int,
                           hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        let zone = TimeZone(identifier: timeZoneID)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = zone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)!
    }

    private func untilInstant(_ rule: RecurrenceRule) -> Date {
        let stamp = rule.rruleString.components(separatedBy: "UNTIL=").last!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: stamp)!
    }
}
