import XCTest
import GRDB
@testable import AssistantStore

final class ClassAnnotationRepositoryTests: XCTestCase {
    private func annotation(id: String, courseId: String = "c1",
                            z: Int = 0) -> ClassAnnotation {
        ClassAnnotation(id: id, courseId: courseId, kind: "stroke",
                        x: 1, y: 2, width: 30, height: 40, zOrder: z,
                        payload: "{\"points\":[[0,0],[1,1]],\"color\":\"#000000\",\"lineWidth\":2}")
    }

    func testMigrationCreatesTable() throws {
        let db = try InMemoryDB.make()
        try db.queue.read { db in
            XCTAssertTrue(try db.tableExists("class_annotation"))
        }
    }

    func testUpsertInsertsThenUpdates() throws {
        let db = try InMemoryDB.make()
        let repo = ClassAnnotationRepository(db: db)
        try repo.upsert(annotation(id: "a1"))
        var rows = try repo.all(courseId: "c1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].x, 1)

        var changed = annotation(id: "a1")
        changed.x = 99
        try repo.upsert(changed)
        rows = try repo.all(courseId: "c1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].x, 99)
    }

    func testAllFiltersByCourseAndOrdersByZOrder() throws {
        let db = try InMemoryDB.make()
        let repo = ClassAnnotationRepository(db: db)
        try repo.upsert(annotation(id: "a2", z: 2))
        try repo.upsert(annotation(id: "a1", z: 1))
        try repo.upsert(annotation(id: "other", courseId: "c2", z: 0))
        let rows = try repo.all(courseId: "c1")
        XCTAssertEqual(rows.map(\.id), ["a1", "a2"])
    }

    func testDeleteRemovesRow() throws {
        let db = try InMemoryDB.make()
        let repo = ClassAnnotationRepository(db: db)
        try repo.upsert(annotation(id: "a1"))
        try repo.delete(id: "a1")
        XCTAssertTrue(try repo.all(courseId: "c1").isEmpty)
    }
}
