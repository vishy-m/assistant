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

    private func seedTree(_ db: AssistantDB) throws {
        let fo = ClassFolderRepository(db: db)
        let fi = ClassFileRepository(db: db)
        let pi = ClassPinRepository(db: db)
        try fo.create(ClassFolder(id: "root", courseId: "c1", parentFolderId: nil, name: "Notes"))
        try fo.create(ClassFolder(id: "sub", courseId: "c1", parentFolderId: "root", name: "Wk1"))
        try fi.create(ClassFile(id: "fA", courseId: "c1", folderId: "root", name: "a.pdf",
                                storedName: "fA.pdf", contentType: "com.adobe.pdf", byteSize: 1))
        try fi.create(ClassFile(id: "fB", courseId: "c1", folderId: "sub", name: "b.pdf",
                                storedName: "fB.pdf", contentType: "com.adobe.pdf", byteSize: 1))
        try pi.upsert(ClassPin(id: "pB", courseId: "c1", fileId: "fB", x: 0, y: 0,
                               width: 10, height: 10))
    }

    func testFolderAndFileCRUD() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        XCTAssertEqual(try ClassFolderRepository(db: db).all(courseId: "c1").count, 2)
        XCTAssertEqual(try ClassFileRepository(db: db).all(courseId: "c1").map(\.id).sorted(),
                       ["fA", "fB"])
        try ClassFileRepository(db: db).move(id: "fB", toFolder: "root")
        XCTAssertEqual(try ClassFileRepository(db: db).find(id: "fB")?.folderId, "root")
    }

    func testDeleteFileReturnsStoredNameAndRemovesPins() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        let stored = try ClassFileRepository(db: db).delete(id: "fB")
        XCTAssertEqual(stored, "fB.pdf")
        XCTAssertNil(try ClassFileRepository(db: db).find(id: "fB"))
        XCTAssertTrue(try ClassPinRepository(db: db).all(courseId: "c1").isEmpty)
    }

    func testDeleteFolderCascadesAndReturnsStoredNames() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        let stored = try ClassFolderRepository(db: db).deleteRecursively(id: "root")
        XCTAssertEqual(stored.sorted(), ["fA.pdf", "fB.pdf"])
        XCTAssertTrue(try ClassFolderRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertTrue(try ClassFileRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertTrue(try ClassPinRepository(db: db).all(courseId: "c1").isEmpty)
    }

    func testPinUpsertListDelete() throws {
        let db = try InMemoryDB.make()
        let repo = ClassPinRepository(db: db)
        try repo.upsert(ClassPin(id: "p1", courseId: "c1", fileId: "f1",
                                 x: 1, y: 2, width: 80, height: 90))
        try repo.upsert(ClassPin(id: "p1", courseId: "c1", fileId: "f1",
                                 x: 5, y: 6, width: 80, height: 90, zOrder: 3))
        let pins = try repo.all(courseId: "c1")
        XCTAssertEqual(pins.count, 1)            // upsert replaced, not duplicated
        XCTAssertEqual(pins.first?.x, 5)
        XCTAssertEqual(pins.first?.zOrder, 3)
        try repo.delete(id: "p1")
        XCTAssertTrue(try repo.all(courseId: "c1").isEmpty)
    }
}
