import XCTest
@testable import AssistantStore
import AssistantShared

final class ClassDetailAssemblerTests: XCTestCase {

    private func course() -> Course {
        Course(id: "c1", name: "OS", term: "Fall", color: "4F6B7A",
               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil,
               professorName: "Dr. Ada", professorEmail: "ada@uni.edu",
               classroom: "ENS 207", iconName: "book.closed")
    }
    private func event(_ id: String, _ start: TimeInterval) -> GCalEventCache {
        GCalEventCache(gcalEventId: id, calendarId: "c", title: id,
                       startAt: Date(timeIntervalSince1970: start),
                       endAt: Date(timeIntervalSince1970: start + 60),
                       location: nil, category: "Misc", lastSyncedAt: Date(),
                       rawJson: "{}", recurringEventId: nil,
                       courseId: "c1", eventType: "class")
    }
    private func task(_ id: String, done: Bool) -> Task {
        Task(id: id, title: id, notes: nil, dueAt: Date(timeIntervalSince1970: 10),
             completedAt: done ? Date() : nil, courseId: "c1", gradeItemId: nil,
             priority: 0, category: "Misc", source: "test")
    }

    func testDetailMapsCourseEventsTasks() {
        let detail = ClassDetailAssembler.detail(
            course: course(), events: [event("e1", 100)],
            tasks: [task("t1", done: false)])
        XCTAssertEqual(detail.id, "c1")
        XCTAssertEqual(detail.professorEmail, "ada@uni.edu")
        XCTAssertEqual(detail.events.map(\.id), ["e1"])
        XCTAssertEqual(detail.tasks.first?.isCompleted, false)
    }

    func testSummaryCountsOpenTasksAndEvents() {
        let summary = ClassDetailAssembler.summary(
            course: course(),
            events: [event("e1", 100), event("e2", 200)],
            tasks: [task("t1", done: false), task("t2", done: true)])
        XCTAssertEqual(summary.openTaskCount, 1)         // only the incomplete one
        XCTAssertEqual(summary.scheduleEventCount, 2)
        XCTAssertEqual(summary.colorHex, "4F6B7A")
    }
}
