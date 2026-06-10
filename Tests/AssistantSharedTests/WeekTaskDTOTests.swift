import XCTest
@testable import AssistantShared

final class WeekTaskDTOTests: XCTestCase {
    func testWeekTaskRoundTrips() throws {
        let task = WeekTask(id: "t1", title: "Submit HW5",
                            dueAt: Date(timeIntervalSince1970: 100), category: "Exam")
        let decoded = try JSONDecoder().decode(
            WeekTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded.id, "t1")
        XCTAssertEqual(decoded.title, "Submit HW5")
        XCTAssertEqual(decoded.category, "Exam")
    }

    func testWeekTasksResponseRoundTrips() throws {
        let response = WeekTasksResponse(tasks: [
            WeekTask(id: "t1", title: "A", dueAt: Date(timeIntervalSince1970: 1),
                     category: "Misc")
        ])
        let decoded = try JSONDecoder().decode(
            WeekTasksResponse.self, from: JSONEncoder().encode(response))
        XCTAssertEqual(decoded.tasks.count, 1)
        XCTAssertEqual(decoded.tasks.first?.id, "t1")
    }
}
