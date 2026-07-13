import XCTest
import GRDB
@testable import AssistantStore

final class SyllabusFolderMigrationTests: XCTestCase {
    // NOTE: InMemoryDB.make() runs ALL migrations including 015, so seeding
    // courses BEFORE 015 requires a manual migrator. Build one that stops
    // right before 015, seed, then finish migrating.
    private func makeSeededDB() throws -> AssistantDB {
        let db = try AssistantDB(queue: DatabaseQueue(), runMigrationsOnInit: false)
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)
        try migrator.migrate(db.queue, upTo: "014_class_annotations")
        try db.queue.write { wdb in
            // Match the course table's real columns (Migration002Course +
            // Migration007CourseCreditHours): id, name, term, color,
            // target_grade, grading_scale_json, syllabus_source_path,
            // created_at, updated_at, credit_hours. There is no "code" column.
            try wdb.execute(sql: """
                INSERT INTO course (id, name, credit_hours, created_at, updated_at)
                VALUES ('c1', 'Operating Systems', 3, datetime('now'), datetime('now')),
                       ('c2', 'Algorithms', 3, datetime('now'), datetime('now'))
                """)
            // c2 already has a root Syllabus folder (must not be duplicated).
            try ClassFolder(id: "existing", courseId: "c2", parentFolderId: nil,
                            name: "Syllabus").insert(wdb)
        }
        try migrator.migrate(db.queue) // runs 015
        return db
    }

    func testBackfillCreatesFolderOncePerCourse() throws {
        let db = try makeSeededDB()
        let repo = ClassFolderRepository(db: db)
        let c1Folders = try repo.all(courseId: "c1")
            .filter { $0.parentFolderId == nil && $0.name.lowercased() == "syllabus" }
        XCTAssertEqual(c1Folders.count, 1)
        let c2Folders = try repo.all(courseId: "c2")
            .filter { $0.parentFolderId == nil && $0.name.lowercased() == "syllabus" }
        XCTAssertEqual(c2Folders.count, 1)
        XCTAssertEqual(c2Folders[0].id, "existing") // untouched, not duplicated
    }

    func testClassFileFind() throws {
        let db = try InMemoryDB.make()
        try db.queue.write { wdb in
            try ClassFile(id: "f1", courseId: "c1", folderId: nil, name: "a.pdf",
                          storedName: "f1.pdf", contentType: "com.adobe.pdf",
                          byteSize: 10).insert(wdb)
        }
        let repo = ClassFileRepository(db: db)
        XCTAssertEqual(try repo.find(id: "f1")?.name, "a.pdf")
        XCTAssertNil(try repo.find(id: "missing"))
    }
}
