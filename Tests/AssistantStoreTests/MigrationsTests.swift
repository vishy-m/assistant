import XCTest
import GRDB
@testable import AssistantStore

final class MigrationsTests: XCTestCase {

    func testInMemoryDBAppliesAllMigrations() throws {
        let db = try InMemoryDB.make()
        let applied = try db.queue.read { try $0.lastAppliedMigration() }
        XCTAssertNotNil(applied)
    }

    func testMigrationsAreIdempotent() throws {
        let db = try InMemoryDB.make()
        // Re-applying should not throw.
        try db.runMigrations()
        try db.runMigrations()
    }

    func testMigration001CreatesSettingTable() throws {
        let db = try InMemoryDB.make()
        let exists = try db.queue.read { db in
            try db.tableExists("setting")
        }
        XCTAssertTrue(exists)
    }

    func testSettingTableHasExpectedColumns() throws {
        let db = try InMemoryDB.make()
        let columns: [String] = try db.queue.read { db in
            try db.columns(in: "setting").map(\.name)
        }
        XCTAssertEqual(Set(columns), Set(["key", "value_json", "updated_at"]))
    }

    func testCourseTablesExist() throws {
        let db = try InMemoryDB.make()
        try db.queue.read { db in
            XCTAssertTrue(try db.tableExists("course"))
            XCTAssertTrue(try db.tableExists("grade_category"))
            XCTAssertTrue(try db.tableExists("grade_item"))
        }
    }

    func testCourseColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "course").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "id", "name", "term", "color",
            "target_grade", "grading_scale_json", "syllabus_source_path",
            "credit_hours", "created_at", "updated_at",
            "professor_name", "professor_email", "classroom", "icon_name"
        ]))
    }

    func testGradeCategoryColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "grade_category").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "id", "course_id", "name", "weight_pct",
            "drop_lowest_n", "drop_highest_n"
        ]))
    }

    func testGradeItemColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "grade_item").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "id", "course_id", "category_id", "name",
            "max_points", "earned_points", "due_at",
            "is_extra_credit", "weight_override_pct",
            "created_at", "updated_at"
        ]))
    }

    func testGradeItemHasForeignKeyOnCategory() throws {
        let db = try InMemoryDB.make()
        let fks: [Row] = try db.queue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('grade_item')")
        }
        XCTAssertTrue(fks.contains { ($0["table"] as String?) == "grade_category" })
        XCTAssertTrue(fks.contains { ($0["table"] as String?) == "course" })
    }

    func testTaskColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "task").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "id", "title", "notes", "due_at", "completed_at",
            "course_id", "grade_item_id", "priority", "category",
            "source", "created_at", "updated_at"
        ]))
    }

    func testGCalEventCacheColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "gcal_event_cache").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "gcal_event_id", "calendar_id", "title",
            "start_at", "end_at", "location", "category",
            "last_synced_at", "raw_json", "recurring_event_id",
            "course_id", "event_type"
        ]))
    }

    func testDeleteCachedSeriesRemovesAllRowsForMaster() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        func cache(_ id: String, master: String?) throws {
            try repo.upsert(GCalEventCache(
                gcalEventId: id, calendarId: "cal1", title: id,
                startAt: Date(), endAt: Date(), location: nil, category: "Misc",
                lastSyncedAt: Date(), rawJson: "{}", recurringEventId: master))
        }
        try cache("m1_a", master: "m1")
        try cache("m1_b", master: "m1")
        try cache("other", master: "m2")
        try cache("m1", master: nil)

        try repo.deleteCachedSeries(recurringEventId: "m1")

        XCTAssertNil(try repo.find(id: "m1_a"))
        XCTAssertNil(try repo.find(id: "m1_b"))
        XCTAssertNotNil(try repo.find(id: "other"))
        XCTAssertNil(try repo.find(id: "m1"))
    }

    func testPendingGCalOpColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "pending_gcal_op").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "id", "op_type", "payload_json", "attempts",
            "last_attempt_at", "created_at"
        ]))
    }

    func testConversationAndMessageColumns() throws {
        let db = try InMemoryDB.make()
        try db.queue.read { db in
            let conv = try db.columns(in: "conversation").map(\.name)
            XCTAssertEqual(Set(conv), Set(["id", "started_at", "last_active_at", "summary"]))
            let msg = try db.columns(in: "message").map(\.name)
            XCTAssertEqual(Set(msg), Set([
                "id", "conversation_id", "role", "content",
                "attached_image_path", "tool_calls_json", "model_used", "created_at"
            ]))
        }
    }

    func testBriefingLogColumns() throws {
        let db = try InMemoryDB.make()
        let cols = try db.queue.read { try $0.columns(in: "briefing_log").map(\.name) }
        XCTAssertEqual(Set(cols), Set([
            "id", "kind", "fired_at", "payload_json",
            "dismissed_at", "acted_on"
        ]))
    }

    func testMigration008SeedsCategoriesAndMigratesGeneric() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)

        // Run migrations up to (and including) 007.
        try migrator.migrate(queue, upTo: "007_course_credit_hours")

        // Insert a gcal_event_cache row and a task row both with category = 'generic'.
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO gcal_event_cache
                    (gcal_event_id, calendar_id, title, start_at, end_at,
                     category, last_synced_at, raw_json)
                VALUES
                    ('ev1', 'cal1', 'Test Event', '2026-01-01T09:00:00Z', '2026-01-01T10:00:00Z',
                     'generic', '2026-01-01T10:00:00Z', '{}')
            """)
            try db.execute(sql: """
                INSERT INTO task
                    (id, title, priority, category, source, created_at, updated_at)
                VALUES
                    ('task1', 'Test Task', 0, 'generic', 'manual',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
            """)
        }

        // Run the remaining migrations (including 008).
        try migrator.migrate(queue)

        try queue.read { db in
            // The category table should contain exactly the 6 seeded names.
            let names = try String.fetchAll(db, sql: "SELECT name FROM category ORDER BY name")
            XCTAssertEqual(Set(names),
                           Set(["Misc", "Class", "Exam", "Assignment", "Club", "Personal"]))
            XCTAssertEqual(names.count, 6)

            // The gcal_event_cache row should have been migrated from 'generic' to 'Misc'.
            let eventCategory = try String.fetchOne(
                db, sql: "SELECT category FROM gcal_event_cache WHERE gcal_event_id = 'ev1'")
            XCTAssertEqual(eventCategory, "Misc")

            // The task row should have been migrated from 'generic' to 'Misc'.
            let taskCategory = try String.fetchOne(
                db, sql: "SELECT category FROM task WHERE id = 'task1'")
            XCTAssertEqual(taskCategory, "Misc")
        }
    }
}

// Small GRDB convenience so tests don't repeat boilerplate.
private extension Database {
    func lastAppliedMigration() throws -> String? {
        let exists = try tableExists("grdb_migrations")
        guard exists else { return nil }
        return try String.fetchOne(self, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier DESC LIMIT 1")
    }
}
