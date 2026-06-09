import XCTest
@testable import AssistantStore

final class DueSoonAggregatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

    private func task(_ id: String, due: Date?, done: Bool = false) -> Task {
        Task(id: id, title: "task-\(id)", notes: nil, dueAt: due,
             completedAt: done ? Date() : nil, courseId: nil, gradeItemId: nil,
             priority: 0, category: "generic", source: "test")
    }

    private func item(_ id: String, due: Date?, earned: Double?) -> GradeItem {
        GradeItem(id: id, courseId: "c1", categoryId: nil, name: "item-\(id)",
                  maxPoints: 100, earnedPoints: earned, dueAt: due,
                  isExtraCredit: false, weightOverridePct: nil)
    }

    func testIncludesTasksAndUngradedItemsInWindow() {
        let entries = DueSoonAggregator.aggregate(
            tasks: [task("t1", due: days(2))],
            gradeItems: [item("g1", due: days(3), earned: nil)],
            now: now)
        XCTAssertEqual(entries.map(\.id), ["t1", "g1"])
    }

    func testExcludesCompletedTasksGradedItemsAndOutOfWindow() {
        let entries = DueSoonAggregator.aggregate(
            tasks: [task("done", due: days(1), done: true),
                    task("far", due: days(30))],
            gradeItems: [item("scored", due: days(1), earned: 90),
                         item("nodue", due: nil, earned: nil)],
            now: now)
        XCTAssertTrue(entries.isEmpty)
    }

    func testOverduePinnedFirstThenBySoonest() {
        let entries = DueSoonAggregator.aggregate(
            tasks: [task("soon", due: days(1)),
                    task("overdue", due: days(-1)),
                    task("later", due: days(4))],
            gradeItems: [],
            now: now)
        XCTAssertEqual(entries.map(\.id), ["overdue", "soon", "later"])
        XCTAssertTrue(entries[0].isOverdue)
        XCTAssertFalse(entries[1].isOverdue)
    }

    func testTaskEntriesCarryTheirCategory() {
        let entries = DueSoonAggregator.aggregate(
            tasks: [task("t1", due: days(1))],
            gradeItems: [item("g1", due: days(2), earned: nil)],
            now: now)
        let t = entries.first { $0.id == "t1" }
        let g = entries.first { $0.id == "g1" }
        XCTAssertEqual(t?.category, "generic")
        XCTAssertNil(g?.category)
    }
}
