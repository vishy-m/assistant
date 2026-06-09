import XCTest
@testable import AssistantStore

final class CategoryRepositoryTests: XCTestCase {

    private func event(_ id: String, category: String, db: AssistantDB) throws {
        try GCalRepository(db: db).upsert(GCalEventCache(
            gcalEventId: id, calendarId: "c", title: id,
            startAt: Date(), endAt: Date(), location: nil, category: category,
            lastSyncedAt: Date(), rawJson: "{}"))
    }

    private func task(_ id: String, category: String, db: AssistantDB) throws {
        try TaskRepository(db: db).insert(Task(
            id: id, title: id, notes: nil, dueAt: nil, completedAt: nil,
            courseId: nil, gradeItemId: nil, priority: 0,
            category: category, source: "test"))
    }

    func testCreateAndListIncludesSeedPlusNew() throws {
        let db = try InMemoryDB.make()
        let repo = CategoryRepository(db: db)
        try repo.create(Category(name: "Travel", colorHex: "112233"))
        XCTAssertTrue(try repo.all().contains { $0.name == "Travel" })
        XCTAssertTrue(try repo.all().contains { $0.name == "Misc" })
    }

    func testResolveMatchesCaseInsensitivelyElseDefault() throws {
        let db = try InMemoryDB.make()
        let repo = CategoryRepository(db: db)
        XCTAssertEqual(try repo.resolve("exam").name, "Exam")
        XCTAssertEqual(try repo.resolve("nonsense").name, "Misc")
        XCTAssertEqual(try repo.resolve(nil).name, "Misc")
    }

    func testRenameCascadesToEventsAndTasks() throws {
        let db = try InMemoryDB.make()
        let repo = CategoryRepository(db: db)
        try event("e1", category: "Exam", db: db)
        try task("t1", category: "Exam", db: db)

        try repo.update(originalName: "Exam",
                        to: Category(name: "Tests", colorHex: "7A5C5C"))

        XCTAssertNil(try repo.find(name: "Exam"))
        XCTAssertNotNil(try repo.find(name: "Tests"))
        XCTAssertEqual(try GCalRepository(db: db).find(id: "e1")?.category, "Tests")
        XCTAssertEqual(try TaskRepository(db: db).all().first { $0.id == "t1" }?.category,
                       "Tests")
    }

    func testDeleteReassignsToDefault() throws {
        let db = try InMemoryDB.make()
        let repo = CategoryRepository(db: db)
        try event("e1", category: "Club", db: db)
        try task("t1", category: "Club", db: db)

        try repo.delete(name: "Club")

        XCTAssertNil(try repo.find(name: "Club"))
        XCTAssertEqual(try GCalRepository(db: db).find(id: "e1")?.category, "Misc")
        XCTAssertEqual(try TaskRepository(db: db).all().first { $0.id == "t1" }?.category,
                       "Misc")
    }

    func testDefaultCategoryCannotBeDeleted() throws {
        let db = try InMemoryDB.make()
        let repo = CategoryRepository(db: db)
        try repo.delete(name: "Misc")
        XCTAssertNotNil(try repo.find(name: "Misc"))
    }

    func testEventsInCategory() throws {
        let db = try InMemoryDB.make()
        try event("e1", category: "Exam", db: db)
        try event("e2", category: "Club", db: db)
        let exam = try CategoryRepository(db: db).events(category: "Exam")
        XCTAssertEqual(exam.map(\.gcalEventId), ["e1"])
    }

    func testEventsForCourseReturnsOnlyThatCourseSorted() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        func ev(_ id: String, _ course: String?, start: TimeInterval) throws {
            try repo.upsert(GCalEventCache(
                gcalEventId: id, calendarId: "c", title: id,
                startAt: Date(timeIntervalSince1970: start),
                endAt: Date(timeIntervalSince1970: start + 60),
                location: nil, category: "Misc", lastSyncedAt: Date(), rawJson: "{}",
                recurringEventId: nil, courseId: course, eventType: "class"))
        }
        try ev("b", "c1", start: 200)
        try ev("a", "c1", start: 100)
        try ev("x", "c2", start: 150)
        try ev("n", nil, start: 50)

        let result = try repo.eventsForCourse("c1")
        XCTAssertEqual(result.map(\.gcalEventId), ["a", "b"])  // only c1, sorted by start
    }

    func testEventCacheRoundTripsClassAndType() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "e1", calendarId: "c", title: "OS Lecture",
            startAt: Date(), endAt: Date(), location: nil, category: "Misc",
            lastSyncedAt: Date(), rawJson: "{}", recurringEventId: nil,
            courseId: "course1", eventType: "class"))
        let loaded = try repo.find(id: "e1")
        XCTAssertEqual(loaded?.courseId, "course1")
        XCTAssertEqual(loaded?.eventType, "class")
    }
}
