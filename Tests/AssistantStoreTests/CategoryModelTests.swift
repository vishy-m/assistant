import XCTest
import GRDB
@testable import AssistantStore

final class CategoryModelTests: XCTestCase {

    func testSeededCategoriesExist() throws {
        let db = try InMemoryDB.make()
        let names = try db.queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM category ORDER BY name")
        }
        XCTAssertEqual(Set(names),
                       Set(["Misc", "Class", "Exam", "Assignment", "Club", "Personal"]))
    }

    func testMiscIsTheDefaultCategory() throws {
        let db = try InMemoryDB.make()
        let defaults = try db.queue.read { db in
            try String.fetchAll(db,
                sql: "SELECT name FROM category WHERE is_default = 1")
        }
        XCTAssertEqual(defaults, ["Misc"])
    }

    func testCategoryRoundTrips() throws {
        let db = try InMemoryDB.make()
        try db.queue.write { db in
            try Category(name: "Travel", colorHex: "4F6B7A").insert(db)
        }
        let fetched = try db.queue.read { db in
            try Category.fetchOne(db, key: "Travel")
        }
        XCTAssertEqual(fetched?.colorHex, "4F6B7A")
        XCTAssertEqual(fetched?.isDefault, false)
    }
}
