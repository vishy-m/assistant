import XCTest
@testable import AssistantShared

final class DashboardDTOsTests: XCTestCase {
    func testDashboardSummaryRoundTrips() throws {
        let summary = DashboardSummary(
            gpa: 3.5, gpaCountedCourses: 2, gpaTotalCourses: 3,
            classes: [ClassStanding(courseId: "c1", courseName: "OS",
                                    currentPct: 91, currentLetter: "A-")],
            recentGrades: [RecentGrade(itemId: "g1", courseName: "OS",
                                       itemName: "Midterm", earnedPct: 88,
                                       enteredAt: Date(timeIntervalSince1970: 1))],
            dueSoon: [DueSoonItem(id: "t1", kind: .task, title: "HW5",
                                  courseName: "OS",
                                  dueAt: Date(timeIntervalSince1970: 2),
                                  isOverdue: false)])
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(DashboardSummary.self, from: data)
        XCTAssertEqual(decoded.gpa, 3.5)
        XCTAssertEqual(decoded.classes.first?.courseName, "OS")
        XCTAssertEqual(decoded.dueSoon.first?.kind, .task)
    }

    func testWeekEventAndRequestsRoundTrip() throws {
        let ev = WeekEvent(id: "e1", title: "Dinner",
                           startAt: Date(timeIntervalSince1970: 10),
                           endAt: Date(timeIntervalSince1970: 20),
                           category: "generic", location: nil)
        XCTAssertEqual(try JSONDecoder().decode(
            WeekEvent.self, from: JSONEncoder().encode(ev)).id, "e1")

        let create = CreateEventRequest(title: "X",
                                        startAt: Date(timeIntervalSince1970: 1),
                                        endAt: Date(timeIntervalSince1970: 2),
                                        location: nil)
        XCTAssertEqual(try JSONDecoder().decode(
            CreateEventRequest.self, from: JSONEncoder().encode(create)).title, "X")

        let update = UpdateEventRequest(eventId: "e1",
                                        startAt: Date(timeIntervalSince1970: 1),
                                        endAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(try JSONDecoder().decode(
            UpdateEventRequest.self, from: JSONEncoder().encode(update)).eventId, "e1")

        let response = WeekEventsResponse(events: [ev])
        XCTAssertEqual(try JSONDecoder().decode(
            WeekEventsResponse.self, from: JSONEncoder().encode(response)).events.count, 1)

        let writeResult = CalendarWriteResult(event: ev, errorMessage: nil)
        XCTAssertEqual(try JSONDecoder().decode(
            CalendarWriteResult.self, from: JSONEncoder().encode(writeResult)).event?.id, "e1")
    }

    func testCreateEventRequestCarriesRecurrence() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 1,
                                  byWeekday: [2, 4], untilDate: nil, count: 10)
        let req = CreateEventRequest(title: "Standup",
                                     startAt: Date(timeIntervalSince1970: 1),
                                     endAt: Date(timeIntervalSince1970: 2),
                                     location: nil, category: "Misc",
                                     recurrence: rule)
        let decoded = try JSONDecoder().decode(
            CreateEventRequest.self, from: JSONEncoder().encode(req))
        XCTAssertEqual(decoded.recurrence, rule)

        // Default stays nil for one-off events.
        let oneOff = CreateEventRequest(title: "X",
                                        startAt: Date(timeIntervalSince1970: 1),
                                        endAt: Date(timeIntervalSince1970: 2),
                                        location: nil)
        XCTAssertNil(oneOff.recurrence)
    }

    func testWeekEventCarriesIsRecurring() throws {
        let ev = WeekEvent(id: "e1", title: "Class",
                           startAt: Date(timeIntervalSince1970: 1),
                           endAt: Date(timeIntervalSince1970: 2),
                           category: "Class", location: nil, isRecurring: true)
        let decoded = try JSONDecoder().decode(
            WeekEvent.self, from: JSONEncoder().encode(ev))
        XCTAssertTrue(decoded.isRecurring)

        // Default stays false.
        let plain = WeekEvent(id: "e2", title: "Y",
                              startAt: Date(timeIntervalSince1970: 1),
                              endAt: Date(timeIntervalSince1970: 2),
                              category: "Misc", location: nil)
        XCTAssertFalse(plain.isRecurring)
    }

    func testWeekEventCarriesClassAndType() throws {
        let ev = WeekEvent(id: "e1", title: "OS", startAt: Date(timeIntervalSince1970: 1),
                           endAt: Date(timeIntervalSince1970: 2), category: "Misc",
                           location: nil, isRecurring: true,
                           courseId: "c1", eventType: "office_hours")
        let decoded = try JSONDecoder().decode(WeekEvent.self,
                                               from: JSONEncoder().encode(ev))
        XCTAssertEqual(decoded.courseId, "c1")
        XCTAssertEqual(decoded.eventType, "office_hours")

        // Legacy payload without the new keys decodes with nils, not a throw.
        let legacy = """
        {"id":"e2","title":"Y","startAt":1,"endAt":2,"category":"Misc","location":null}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(WeekEvent.self, from: legacy)
        XCTAssertNil(old.courseId)
        XCTAssertNil(old.eventType)
    }

    func testCreateEventRequestCarriesClassAndType() throws {
        let req = CreateEventRequest(title: "X", startAt: Date(timeIntervalSince1970: 1),
                                     endAt: Date(timeIntervalSince1970: 2), location: nil,
                                     category: "Misc", recurrence: nil,
                                     courseId: "c1", eventType: "exam")
        let decoded = try JSONDecoder().decode(CreateEventRequest.self,
                                               from: JSONEncoder().encode(req))
        XCTAssertEqual(decoded.courseId, "c1")
        XCTAssertEqual(decoded.eventType, "exam")
    }

    func testUpdateEventRequestCarriesTitle() throws {
        let req = UpdateEventRequest(eventId: "e1",
                                     startAt: Date(timeIntervalSince1970: 1),
                                     endAt: Date(timeIntervalSince1970: 2),
                                     title: "New Name")
        let decoded = try JSONDecoder().decode(
            UpdateEventRequest.self, from: JSONEncoder().encode(req))
        XCTAssertEqual(decoded.title, "New Name")

        // Legacy payload without `title` decodes to nil, not a throw.
        let legacy = #"{"eventId":"e1","startAt":1,"endAt":2}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(UpdateEventRequest.self, from: legacy).title)

        // Default stays nil.
        XCTAssertNil(UpdateEventRequest(eventId: "e",
                                        startAt: Date(), endAt: Date()).title)
    }

    func testClassDetailRoundTrips() throws {
        let detail = ClassDetail(
            id: "c1", name: "OS", term: "Fall", colorHex: "4F6B7A", iconName: "book.closed",
            professorName: "Dr. Ada", professorEmail: "ada@uni.edu", classroom: "ENS 207",
            events: [ClassEventItem(id: "e1", title: "Lecture",
                                    startAt: Date(timeIntervalSince1970: 1),
                                    endAt: Date(timeIntervalSince1970: 2), eventType: "class")],
            tasks: [ClassTaskItem(id: "t1", title: "HW1",
                                  dueAt: Date(timeIntervalSince1970: 3), isCompleted: false)])
        let decoded = try JSONDecoder().decode(ClassDetail.self,
                                               from: JSONEncoder().encode(detail))
        XCTAssertEqual(decoded.events.first?.eventType, "class")
        XCTAssertEqual(decoded.tasks.first?.title, "HW1")

        let summary = ClassSummary(id: "c1", name: "OS", term: "Fall", colorHex: "4F6B7A",
                                   iconName: "book.closed", professorName: "Dr. Ada",
                                   classroom: "ENS 207", openTaskCount: 2, scheduleEventCount: 3)
        let ds = try JSONDecoder().decode(ClassSummary.self,
                                          from: JSONEncoder().encode(summary))
        XCTAssertEqual(ds.openTaskCount, 2)
    }
}
