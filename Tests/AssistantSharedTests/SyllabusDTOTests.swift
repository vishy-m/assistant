import XCTest
@testable import AssistantShared

final class SyllabusDTOTests: XCTestCase {
    func testTitles() {
        XCTAssertEqual(SyllabusTitles.homework(className: "OS"), "[hmwk] [OS]")
        XCTAssertEqual(SyllabusTitles.exam(className: "OS"), "[exam] [OS]")
        XCTAssertEqual(SyllabusTitles.officeHours(person: "Prof. Smith", className: "OS"),
                       "[OH] [Prof. Smith] [OS]")
        XCTAssertEqual(SyllabusTitles.officeHours(person: nil, className: "OS"), "[OH] [OS]")
        XCTAssertEqual(SyllabusTitles.officeHours(person: "  ", className: "OS"), "[OH] [OS]")
        XCTAssertEqual(SyllabusTitles.event(kind: .lecture, className: "OS"), "[lecture] [OS]")
        XCTAssertEqual(SyllabusTitles.event(kind: .review, className: "OS"), "[review] [OS]")
        XCTAssertEqual(SyllabusTitles.event(kind: .exam, className: "OS"), "[exam] [OS]")
        XCTAssertEqual(SyllabusTitles.event(kind: .homeworkPattern, className: "OS"), "[hmwk] [OS]")
        XCTAssertEqual(SyllabusTitles.event(kind: .officeHours, className: "OS"), "[OH] [OS]")
    }

    func testScanResultRoundTripAllStatuses() throws {
        let event = SyllabusProposedEvent(
            kind: .officeHours, title: "[OH] [Prof. Smith] [OS]",
            startAt: Date(timeIntervalSince1970: 1_700_000_000),
            endAt: Date(timeIntervalSince1970: 1_700_003_600),
            location: "GDC 4.802", personName: "Prof. Smith",
            recurrence: RecurrenceRule(frequency: .weekly, interval: 1,
                                       byWeekday: [4], untilDate: nil, count: nil))
        let task = SyllabusProposedTask(
            title: "HW3: Paging", dueAt: Date(timeIntervalSince1970: 1_700_100_000),
            notes: "Submit on Gradescope")
        for status: SyllabusScanStatus in [.ok, .nothingToScan, .llmUnavailable,
                                           .failed("provider down")] {
            let result = SyllabusScanResult(fileId: "f1", status: status,
                                            events: [event], tasks: [task])
            let back = try JSONDecoder().decode(SyllabusScanResult.self,
                                                from: JSONEncoder().encode(result))
            XCTAssertEqual(back, result)
        }
    }

    func testScanResultIdentityIsFileId() {
        let r = SyllabusScanResult(fileId: "abc", status: .ok, events: [], tasks: [])
        XCTAssertEqual(r.id, "abc")
    }
}
