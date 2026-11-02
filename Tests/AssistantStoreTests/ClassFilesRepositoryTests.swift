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
        let removed = try ClassFolderRepository(db: db).deleteRecursively(id: "root")
        XCTAssertEqual(removed.map(\.storedName).sorted(), ["fA.pdf", "fB.pdf"])
        XCTAssertEqual(Set(removed.map(\.courseId)), ["c1"])
        XCTAssertTrue(try ClassFolderRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertTrue(try ClassFileRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertTrue(try ClassPinRepository(db: db).all(courseId: "c1").isEmpty)
    }

    // MARK: - Folder cycles (A3-02)

    func testMoveFolderUnderItsDescendantThrowsAndLeavesParent() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        let repo = ClassFolderRepository(db: db)
        XCTAssertThrowsError(try repo.move(id: "root", toParent: "sub"))
        XCTAssertThrowsError(try repo.move(id: "root", toParent: "root"))
        XCTAssertNil(try repo.find(id: "root")?.parentFolderId)
    }

    func testMoveFolderValidatesParentCourseAndExistence() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        let repo = ClassFolderRepository(db: db)
        try repo.create(ClassFolder(id: "other", courseId: "c2", parentFolderId: nil, name: "X"))
        XCTAssertThrowsError(try repo.move(id: "sub", toParent: "other"))
        XCTAssertThrowsError(try repo.move(id: "sub", toParent: "ghost"))
        XCTAssertEqual(try repo.find(id: "sub")?.parentFolderId, "root")
        // Legal moves still work: promote to root, and move under a cousin.
        try repo.create(ClassFolder(id: "cousin", courseId: "c1", parentFolderId: nil, name: "C"))
        try repo.move(id: "sub", toParent: "cousin")
        XCTAssertEqual(try repo.find(id: "sub")?.parentFolderId, "cousin")
        try repo.move(id: "sub", toParent: nil)
        XCTAssertNil(try repo.find(id: "sub")?.parentFolderId)
        XCTAssertNoThrow(try repo.move(id: "missing", toParent: nil))
    }

    func testCreateFolderRejectsSelfParentAndForeignParent() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        let repo = ClassFolderRepository(db: db)
        XCTAssertThrowsError(try repo.create(
            ClassFolder(id: "self", courseId: "c1", parentFolderId: "self", name: "S")))
        XCTAssertThrowsError(try repo.create(
            ClassFolder(id: "x", courseId: "c2", parentFolderId: "root", name: "X")))
        XCTAssertThrowsError(try repo.create(
            ClassFolder(id: "y", courseId: "c1", parentFolderId: "ghost", name: "Y")))
        XCTAssertNil(try repo.find(id: "self"))
        XCTAssertNil(try repo.find(id: "x"))
    }

    func testDeleteRecursivelyFinishesOnPreexistingCycle() throws {
        let db = try InMemoryDB.make()
        try db.queue.write { db in
            try ClassFolder(id: "A", courseId: "c1", parentFolderId: "B", name: "A").insert(db)
            try ClassFolder(id: "B", courseId: "c1", parentFolderId: "A", name: "B").insert(db)
            try ClassFolder(id: "S", courseId: "c1", parentFolderId: "S", name: "S").insert(db)
            try ClassFile(id: "f", courseId: "c1", folderId: "B", name: "f", storedName: "f.pdf",
                          contentType: "x", byteSize: 1).insert(db)
        }
        let repo = ClassFolderRepository(db: db)
        let removed = try repo.deleteRecursively(id: "A")
        XCTAssertEqual(removed.map(\.storedName), ["f.pdf"])
        XCTAssertNil(try repo.find(id: "A"))
        XCTAssertNil(try repo.find(id: "B"))
        XCTAssertEqual(try repo.deleteRecursively(id: "S"), [])
        XCTAssertNil(try repo.find(id: "S"))
    }

    func testFilesInSubtreeListsRowsWithoutDeleting() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        let files = try ClassFolderRepository(db: db).filesInSubtree(id: "root")
        XCTAssertEqual(files.map(\.id).sorted(), ["fA", "fB"])
        XCTAssertEqual(try ClassFileRepository(db: db).all(courseId: "c1").count, 2)
    }

    // MARK: - Cross-course moves (A3-03)

    func testMoveFileToOtherCoursesFolderThrows() throws {
        let db = try InMemoryDB.make()
        try seedTree(db)
        try ClassFolderRepository(db: db).create(
            ClassFolder(id: "foB", courseId: "c2", parentFolderId: nil, name: "B"))
        let files = ClassFileRepository(db: db)
        XCTAssertThrowsError(try files.move(id: "fA", toFolder: "foB"))
        XCTAssertThrowsError(try files.move(id: "fA", toFolder: "ghost"))
        XCTAssertEqual(try files.find(id: "fA")?.folderId, "root")
        try files.move(id: "fA", toFolder: nil)
        XCTAssertNil(try files.find(id: "fA")?.folderId)
    }

    func testDeleteFolderReturnsEachFilesOwnCourse() throws {
        let db = try InMemoryDB.make()
        try db.queue.write { db in
            try ClassFolder(id: "foB", courseId: "c2", parentFolderId: nil, name: "B").insert(db)
            // Legacy cross-linked row: file of course c1 sitting in c2's folder.
            try ClassFile(id: "fx", courseId: "c1", folderId: "foB", name: "x",
                          storedName: "fx.pdf", contentType: "x", byteSize: 1).insert(db)
        }
        let removed = try ClassFolderRepository(db: db).deleteRecursively(id: "foB")
        XCTAssertEqual(removed.map(\.courseId), ["c1"])
        XCTAssertEqual(removed.map(\.storedName), ["fx.pdf"])
    }

    func testDeleteMissingFileReturnsNil() throws {
        let db = try InMemoryDB.make()
        XCTAssertNil(try ClassFileRepository(db: db).delete(id: "nope"))
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
