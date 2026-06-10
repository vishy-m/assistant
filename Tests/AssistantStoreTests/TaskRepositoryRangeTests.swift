import XCTest
@testable import AssistantStore

final class TaskRepositoryRangeTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ days: Double) -> Date { base.addingTimeInterval(days * 86_400) }

    private func makeTask(_ id: String, due: Date?, done: Bool = false) -> Task {
        Task(id: id, title: "task-\(id)", notes: nil, dueAt: due,
             completedAt: done ? Date() : nil, courseId: nil, gradeItemId: nil,
             priority: 0, category: "Misc", source: "test")
    }

    func testDueInRangeIncludesOnlyIncompleteDatedTasksInWindow() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        try repo.insert(makeTask("inside", due: at(2)))
        try repo.insert(makeTask("before", due: at(-2)))
        try repo.insert(makeTask("after", due: at(20)))
        try repo.insert(makeTask("done", due: at(2), done: true))
        try repo.insert(makeTask("nodue", due: nil))

        let result = try repo.dueInRange(start: base, end: at(7))
        XCTAssertEqual(result.map(\.id), ["inside"])
    }

    func testSetDueAtUpdatesAndPersists() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        try repo.insert(makeTask("t1", due: at(1)))

        try repo.setDueAt(id: "t1", dueAt: at(3))

        let fetched = try repo.find(id: "t1")
        XCTAssertEqual(fetched?.dueAt?.timeIntervalSince1970 ?? 0,
                       at(3).timeIntervalSince1970, accuracy: 1.0)
    }
}
