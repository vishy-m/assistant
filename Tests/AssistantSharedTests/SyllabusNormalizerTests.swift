import XCTest
@testable import AssistantShared

final class SyllabusNormalizerTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }
    // Monday 2026-08-24, 09:00 local.
    private var scanDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
    }

    private func normalize(_ raw: RawSyllabusExtraction)
        -> (events: [SyllabusProposedEvent], tasks: [SyllabusProposedTask]) {
        SyllabusNormalizer.normalize(raw, className: "OS", scanDate: scanDate,
                                     calendar: calendar)
    }

    func testRecurringOfficeHoursNormalization() {
        let raw = RawSyllabusExtraction(
            semesterEnd: "2026-12-11",
            recurringEvents: [RawRecurring(kind: "office_hours", person: "Prof. Smith",
                                           weekdays: ["wednesday"], startTime: "14:00",
                                           endTime: "15:30", location: "GDC 4.802")],
            datedEvents: [], deadlines: [])
        let out = normalize(raw)
        XCTAssertEqual(out.events.count, 1)
        let e = out.events[0]
        XCTAssertEqual(e.kind, .officeHours)
        XCTAssertEqual(e.title, "[OH] [Prof. Smith] [OS]")
        XCTAssertEqual(e.location, "GDC 4.802")
        // First occurrence: the next Wednesday on/after Monday Aug 24 = Aug 26.
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: e.startAt)
        XCTAssertEqual([comps.year, comps.month, comps.day, comps.hour, comps.minute],
                       [2026, 8, 26, 14, 0])
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: e.endAt).hour, 15)
        let rule = try! XCTUnwrap(e.recurrence)
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.byWeekday, [4]) // Wednesday
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day],
                                               from: try! XCTUnwrap(rule.untilDate)).day, 11)
    }

    func testUntilFallbackIs16Weeks() {
        let raw = RawSyllabusExtraction(
            semesterEnd: nil,
            recurringEvents: [RawRecurring(kind: "homework", person: nil,
                                           weekdays: ["wednesday"], startTime: "23:59",
                                           endTime: nil, location: nil)],
            datedEvents: [], deadlines: [])
        let e = normalize(raw).events[0]
        XCTAssertEqual(e.kind, .homeworkPattern)
        XCTAssertEqual(e.title, "[hmwk] [OS]")
        let until = try! XCTUnwrap(e.recurrence?.untilDate)
        XCTAssertEqual(until.timeIntervalSince(scanDate), 112 * 24 * 3600, accuracy: 2)
        // Missing end time defaults to start + 1h.
        XCTAssertEqual(e.endAt.timeIntervalSince(e.startAt), 3600, accuracy: 1)
    }

    func testDatedExamAndMalformedEntriesDropped() {
        let raw = RawSyllabusExtraction(
            semesterEnd: nil,
            recurringEvents: [RawRecurring(kind: "office_hours", person: nil,
                                           weekdays: [], startTime: "10:00",
                                           endTime: nil, location: nil)], // no weekdays -> drop
            datedEvents: [
                RawDated(kind: "exam", date: "2026-10-08", startTime: "19:00",
                         endTime: "21:00", location: "UTC 2.102A", person: nil),
                RawDated(kind: "exam", date: "not a date", startTime: nil,
                         endTime: nil, location: nil, person: nil) // -> drop
            ],
            deadlines: [])
        let out = normalize(raw)
        XCTAssertEqual(out.events.count, 1)
        let e = out.events[0]
        XCTAssertEqual(e.title, "[exam] [OS]")
        XCTAssertNil(e.recurrence)
        let comps = calendar.dateComponents([.month, .day, .hour], from: e.startAt)
        XCTAssertEqual([comps.month, comps.day, comps.hour], [10, 8, 19])
    }

    func testDeadlinesBecomeTasksWithDefaultTime() {
        let raw = RawSyllabusExtraction(
            semesterEnd: nil, recurringEvents: [], datedEvents: [],
            deadlines: [RawDeadline(name: "HW3: Paging", date: "2026-10-08",
                                    time: nil, notes: "Gradescope"),
                        RawDeadline(name: "Broken", date: nil, time: nil, notes: nil)])
        let out = normalize(raw)
        XCTAssertEqual(out.tasks.count, 1)
        let t = out.tasks[0]
        XCTAssertEqual(t.title, "HW3: Paging")
        XCTAssertEqual(t.notes, "Gradescope")
        let comps = calendar.dateComponents([.month, .day, .hour, .minute], from: t.dueAt)
        XCTAssertEqual([comps.month, comps.day, comps.hour, comps.minute], [10, 8, 23, 59])
    }

    func testAllWeekdayNamesMap() {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday",
                     "friday", "saturday"]
        let raw = RawSyllabusExtraction(
            semesterEnd: nil,
            recurringEvents: [RawRecurring(kind: "lecture", person: nil, weekdays: names,
                                           startTime: "08:00", endTime: "09:00",
                                           location: nil)],
            datedEvents: [], deadlines: [])
        let e = normalize(raw).events[0]
        XCTAssertEqual(e.recurrence?.byWeekday.sorted(), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(e.title, "[lecture] [OS]")
    }

    func testPromptContainsCourseTodayPriorityRuleAndText() {
        let p = SyllabusPrompt.build(className: "OS", todayISO: "2026-08-24",
                                     documentText: "THE DOCUMENT BODY")
        XCTAssertTrue(p.contains("OS"))
        XCTAssertTrue(p.contains("2026-08-24"))
        XCTAssertTrue(p.contains("THE DOCUMENT BODY"))
        XCTAssertTrue(p.lowercased().contains("dated"))     // priority rule present
        XCTAssertEqual(SyllabusPrompt.toolName, "record_extraction")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(
            with: Data(SyllabusPrompt.toolSchemaJSON.utf8)))
    }
}
