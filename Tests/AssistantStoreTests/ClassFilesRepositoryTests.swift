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

    func testModelsRoundTripThroughDB() throws {
        let db = try InMemoryDB.make()
        try db.queue.write { wdb in
            try ClassFolder(id: "fo1", courseId: "c1", parentFolderId: nil,
                            name: "Notes", sortOrder: 0).insert(wdb)
            try ClassFile(id: "fi1", courseId: "c1", folderId: "fo1", name: "w1.pdf",
                          storedName: "fi1.pdf", contentType: "com.adobe.pdf",
                          byteSize: 10).insert(wdb)
            try ClassPin(id: "p1", courseId: "c1", fileId: "fi1", x: 1, y: 2,
                         width: 100, height: 120, rotation: 0, zOrder: 0).insert(wdb)
        }
        try db.queue.read { rdb in
            XCTAssertEqual(try ClassFolder.fetchOne(rdb, key: "fo1")?.name, "Notes")
            XCTAssertEqual(try ClassFile.fetchOne(rdb, key: "fi1")?.storedName, "fi1.pdf")
            XCTAssertEqual(try ClassPin.fetchOne(rdb, key: "p1")?.width, 100)
        }
    }
}
