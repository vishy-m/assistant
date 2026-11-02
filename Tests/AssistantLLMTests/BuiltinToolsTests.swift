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

    func testListTasksThisWeekUsesTheWeekInterval() async throws {
        let cal = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let interval = try XCTUnwrap(cal.dateInterval(of: .weekOfYear, for: now))
        let (registry, taskRepo) = try makeRegistry(clock: { now })
        try insert(taskRepo, id: "in-early", title: "Early this week", dueAt: interval.start.addingTimeInterval(60))
        try insert(taskRepo, id: "in-late", title: "Late this week", dueAt: interval.end.addingTimeInterval(-60))
        try insert(taskRepo, id: "out", title: "After this week", dueAt: interval.end.addingTimeInterval(60))

        let result = try await registry.invoke(name: "list_tasks", argumentsJSON: #"{"filter":"This_Week"}"#)
        XCTAssertTrue(result.contains("Early this week"))
        XCTAssertTrue(result.contains("Late this week"))
        XCTAssertFalse(result.contains("After this week"))
    }

    func testListTasksAllIncludesUndatedAndOmitsCompleted() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (registry, taskRepo) = try makeRegistry(clock: { now })
        try insert(taskRepo, id: "open", title: "Undated open", dueAt: nil)
        try insert(taskRepo, id: "later", title: "Far future", dueAt: now.addingTimeInterval(86400 * 40))
        try insert(taskRepo, id: "done", title: "Finished work", dueAt: now, completedAt: now)

        let all = try await registry.invoke(name: "list_tasks", argumentsJSON: #"{"filter":"all"}"#)
        XCTAssertTrue(all.contains("Undated open"))
        XCTAssertTrue(all.contains("Far future"))
        XCTAssertFalse(all.contains("Finished work"))

        let today = try await registry.invoke(name: "list_tasks", argumentsJSON: #"{"filter":"today"}"#)
        XCTAssertFalse(today.contains("Undated open"))
    }

    func testListTasksUnknownFilterDoesNotReturnToday() async throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let (registry, taskRepo) = try makeRegistry(clock: { now })
        try insert(taskRepo, id: "t1", title: "Visible today", dueAt: now.addingTimeInterval(3600))

        let unknown = try await registry.invoke(name: "list_tasks", argumentsJSON: #"{"filter":"next_year"}"#)
        XCTAssertTrue(unknown.contains("unsupported filter"))
        XCTAssertFalse(unknown.contains("Visible today"))

        let empty = try await registry.invoke(name: "list_tasks", argumentsJSON: #"{"filter":""}"#)
        XCTAssertTrue(empty.contains("unsupported filter"))
        XCTAssertFalse(empty.contains("Visible today"))
    }

    func testCreateTaskRejectsUnparseableDueDate() async throws {
        let (registry, taskRepo) = try makeRegistry()
        let result = try await registry.invoke(
            name: "create_task",
            argumentsJSON: #"{"title":"Later","due_at":"tomorrow at five"}"#)
        XCTAssertTrue(result.contains("bad ISO date"))
        XCTAssertTrue(try taskRepo.all().isEmpty)
    }

    func testCreateTaskOmitsDueDate() async throws {
        let (registry, taskRepo) = try makeRegistry()
        _ = try await registry.invoke(name: "create_task", argumentsJSON: #"{"title":"No due"}"#)
        let tasks = try taskRepo.all()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "No due")
        XCTAssertNil(tasks[0].dueAt)
    }

    func testCreateTaskWhitespaceDueDateIsUndated() async throws {
        let (registry, taskRepo) = try makeRegistry()
        _ = try await registry.invoke(
            name: "create_task",
            argumentsJSON: #"{"title":"Blank due","due_at":"   "}"#)
        let tasks = try taskRepo.all()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Blank due")
        XCTAssertNil(tasks[0].dueAt)
    }

    private func makeRegistry(clock: @escaping @Sendable () -> Date = { Date() }) throws -> (ToolRegistry, TaskRepository) {
        let db = try InMemoryDB.make()
        let taskRepo = TaskRepository(db: db)
        var registry = ToolRegistry()
        BuiltinTools.registerTaskTools(into: &registry,
                                       taskRepo: taskRepo,
                                       gcalRepo: GCalRepository(db: db),
                                       categoryRepo: CategoryRepository(db: db),
                                       clock: clock)
        return (registry, taskRepo)
    }

    private func insert(_ taskRepo: TaskRepository, id: String, title: String,
                        dueAt: Date?, completedAt: Date? = nil) throws {
        try taskRepo.insert(AssistantStore.Task(
            id: id, title: title, notes: nil,
            dueAt: dueAt, completedAt: completedAt,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: "Misc", source: "manual"))
    }
}
