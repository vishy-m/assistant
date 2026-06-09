import XCTest
@testable import AssistantStore

final class TaskRepositoryTests: XCTestCase {

    func testInsertAndFind() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        let t = AssistantStore.Task(
            id: "t1", title: "Write design", notes: nil,
            dueAt: Date(timeIntervalSinceNow: 3600), completedAt: nil,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: "generic", source: "manual")
        try repo.insert(t)
        XCTAssertEqual(try repo.find(id: "t1")?.title, "Write design")
    }

    func testListDueOnDate() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        try repo.insert(AssistantStore.Task(
            id: "today", title: "Today task", notes: nil,
            dueAt: today.addingTimeInterval(7200), completedAt: nil,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: "generic", source: "manual"))
        try repo.insert(AssistantStore.Task(
            id: "tomorrow", title: "Tomorrow task", notes: nil,
            dueAt: tomorrow.addingTimeInterval(7200), completedAt: nil,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: "generic", source: "manual"))

        let dueToday = try repo.dueOn(date: today)
        XCTAssertEqual(dueToday.count, 1)
        XCTAssertEqual(dueToday.first?.id, "today")
    }

    func testCompleteExcludesFromDueQuery() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        try repo.insert(AssistantStore.Task(
            id: "t1", title: "x", notes: nil,
            dueAt: today.addingTimeInterval(7200), completedAt: nil,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: "generic", source: "manual"))
        try repo.complete(id: "t1")
        XCTAssertTrue(try repo.dueOn(date: today).isEmpty)
        XCTAssertNotNil(try repo.find(id: "t1")?.completedAt)
    }
}
