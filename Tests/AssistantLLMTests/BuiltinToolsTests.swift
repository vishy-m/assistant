import XCTest
@testable import AssistantLLM
@testable import AssistantStore

final class BuiltinToolsTests: XCTestCase {

    func testCreateTaskTool() async throws {
        let db = try InMemoryDB.make()
        let taskRepo = TaskRepository(db: db)
        let gcalRepo = GCalRepository(db: db)
        let categoryRepo = CategoryRepository(db: db)
        var registry = ToolRegistry()
        BuiltinTools.registerTaskTools(into: &registry,
                                       taskRepo: taskRepo,
                                       gcalRepo: gcalRepo,
                                       categoryRepo: categoryRepo,
                                       clock: { Date(timeIntervalSince1970: 1_700_000_000) })

        let resultJSON = try await registry.invoke(
            name: "create_task",
            argumentsJSON: #"{"title":"Write design","due_at":"2026-05-14T17:00:00Z","category":"assignment_due"}"#)

        XCTAssertTrue(resultJSON.contains("\"id\""))
        let allTasks = try taskRepo.dueOn(date: ISO8601DateFormatter().date(from: "2026-05-14T17:00:00Z")!)
        XCTAssertEqual(allTasks.first?.title, "Write design")
        // "assignment_due" is not a known category → resolves to the default "Misc"
        XCTAssertEqual(allTasks.first?.category, "Misc")
    }

    func testListTasksTodayTool() async throws {
        let db = try InMemoryDB.make()
        let taskRepo = TaskRepository(db: db)
        let gcalRepo = GCalRepository(db: db)
        let categoryRepo = CategoryRepository(db: db)
        // Anchor to local noon so `today + 1h` can't roll into tomorrow when the
        // suite runs near midnight (the filter derives "today" from this clock).
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        try taskRepo.insert(AssistantStore.Task(
            id: "t1", title: "Today task", notes: nil,
            dueAt: today.addingTimeInterval(3600), completedAt: nil,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: "Misc", source: "manual"))

        var registry = ToolRegistry()
        BuiltinTools.registerTaskTools(into: &registry,
                                       taskRepo: taskRepo,
                                       gcalRepo: gcalRepo,
                                       categoryRepo: categoryRepo,
                                       clock: { today })
        let result = try await registry.invoke(name: "list_tasks", argumentsJSON: #"{"filter":"today"}"#)
        XCTAssertTrue(result.contains("Today task"))
    }

    func testCreateTaskDefaultCategoryIsMisc() async throws {
        let db = try InMemoryDB.make()
        let taskRepo = TaskRepository(db: db)
        let gcalRepo = GCalRepository(db: db)
        let categoryRepo = CategoryRepository(db: db)
        var registry = ToolRegistry()
        BuiltinTools.registerTaskTools(into: &registry,
                                       taskRepo: taskRepo,
                                       gcalRepo: gcalRepo,
                                       categoryRepo: categoryRepo,
                                       clock: { Date(timeIntervalSince1970: 1_700_000_000) })

        _ = try await registry.invoke(
            name: "create_task",
            argumentsJSON: #"{"title":"No category task","due_at":"2026-05-14T17:00:00Z"}"#)

        let allTasks = try taskRepo.dueOn(date: ISO8601DateFormatter().date(from: "2026-05-14T17:00:00Z")!)
        XCTAssertEqual(allTasks.first?.title, "No category task")
        XCTAssertEqual(allTasks.first?.category, "Misc")
    }

    func testCreateTaskCanonicalizesLowercaseCategory() async throws {
        let db = try InMemoryDB.make()
        let taskRepo = TaskRepository(db: db)
        let gcalRepo = GCalRepository(db: db)
        let categoryRepo = CategoryRepository(db: db)
        var registry = ToolRegistry()
        BuiltinTools.registerTaskTools(into: &registry,
                                       taskRepo: taskRepo,
                                       gcalRepo: gcalRepo,
                                       categoryRepo: categoryRepo,
                                       clock: { Date(timeIntervalSince1970: 1_700_000_000) })

        _ = try await registry.invoke(
            name: "create_task",
            argumentsJSON: #"{"title":"Mid-term","due_at":"2026-05-14T17:00:00Z","category":"exam"}"#)

        let allTasks = try taskRepo.dueOn(date: ISO8601DateFormatter().date(from: "2026-05-14T17:00:00Z")!)
        XCTAssertEqual(allTasks.first?.title, "Mid-term")
        XCTAssertEqual(allTasks.first?.category, "Exam")
    }
}
