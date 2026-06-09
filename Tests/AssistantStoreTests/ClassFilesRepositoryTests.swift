import XCTest
import GRDB
@testable import AssistantStore

final class ClassFilesRepositoryTests: XCTestCase {
    func testMigrationCreatesTables() throws {
        let db = try InMemoryDB.make()
        try db.queue.read { db in
            XCTAssertTrue(try db.tableExists("class_folder"))
            XCTAssertTrue(try db.tableExists("class_file"))
            XCTAssertTrue(try db.tableExists("class_pin"))
        }
    }
}
