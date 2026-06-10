import XCTest
@testable import AssistantStore

final class TaskCompletionTests: XCTestCase {

    private func makeTask(_ id: String, done: Bool = false) -> Task {
        Task(id: id, title: "task-\(id)", notes: nil, dueAt: nil,
             completedAt: done ? Date() : nil, courseId: nil, gradeItemId: nil,
             priority: 1, category: "Misc", source: "test")
    }

    func testSetCompletedMarksAndUnmarks() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        try repo.insert(makeTask("t1"))

        try repo.setCompleted(id: "t1", completed: true)
        XCTAssertNotNil(try repo.find(id: "t1")?.completedAt)

        try repo.setCompleted(id: "t1", completed: false)
        XCTAssertNil(try repo.find(id: "t1")?.completedAt)
    }

    func testDeleteCompletedRemovesOnlyCompleted() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        try repo.insert(makeTask("open", done: false))
        try repo.insert(makeTask("done", done: true))

        try repo.deleteCompleted()

        XCTAssertNotNil(try repo.find(id: "open"))
        XCTAssertNil(try repo.find(id: "done"))
    }

    func testTasksNoteRoundTrip() throws {
        let db = try InMemoryDB.make()
        let repo = SettingRepository(db: db)

        XCTAssertNil(try repo.get("tasks_scratchpad"))

        try repo.set("tasks_scratchpad", value: "remember to submit the lab report")
        XCTAssertEqual(try repo.get("tasks_scratchpad"),
                       "remember to submit the lab report")

        try repo.set("tasks_scratchpad", value: "buy a new notebook")
        XCTAssertEqual(try repo.get("tasks_scratchpad"), "buy a new notebook")
    }

    func testProgressFraction() {
        XCTAssertEqual(TaskProgress.fraction([]), 0, accuracy: 0.0001)
        XCTAssertEqual(TaskProgress.fraction([makeTask("a", done: true),
                                              makeTask("b", done: true)]),
                       1, accuracy: 0.0001)
        XCTAssertEqual(TaskProgress.fraction([makeTask("a", done: true),
                                              makeTask("b", done: false),
                                              makeTask("c", done: false),
                                              makeTask("d", done: false)]),
                       0.25, accuracy: 0.0001)
    }
}
