import XCTest
import GRDB
@testable import AssistantStore

final class ClassFileImporterTests: XCTestCase {
    private var root: URL!
    private var storage: ClassFileStorage!
    private var db: AssistantDB!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClassFileImporterTests-\(UUID().uuidString)")
        storage = ClassFileStorage(base: root.appendingPathComponent("ClassFiles"))
        db = try InMemoryDB.make()
        try CourseRepository(db: db).insert(Course(
            id: "c1", name: "OS", term: nil, color: nil, targetGrade: nil,
            gradingScaleJson: nil, syllabusSourcePath: nil))
        try CourseRepository(db: db).insert(Course(
            id: "c2", name: "DB", term: nil, color: nil, targetGrade: nil,
            gradingScaleJson: nil, syllabusSourcePath: nil))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var importer: ClassFileImporter { ClassFileImporter(db: db, storage: storage) }

    private func filesOnDisk(_ courseId: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(
            atPath: storage.base.appendingPathComponent(courseId).path)) ?? []
    }

    func testImportWritesServerNamedFileAndRow() throws {
        let ok = try importer.importFile(id: "f1", courseId: "c1", folderId: nil,
                                         name: "Week 1.PDF", contentType: "com.adobe.pdf",
                                         bytes: Data("pdf".utf8))
        XCTAssertTrue(ok)
        let row = try XCTUnwrap(ClassFileRepository(db: db).find(id: "f1"))
        XCTAssertEqual(row.byteSize, 3)
        XCTAssertTrue(row.storedName.hasSuffix(".PDF"))
        XCTAssertNotEqual(row.storedName, "Week 1.PDF")
        let url = try storage.resolve(courseId: "c1", storedName: row.storedName)
        XCTAssertEqual(try Data(contentsOf: url), Data("pdf".utf8))
        let real = url.resolvingSymlinksInPath().path
        XCTAssertTrue(real.hasPrefix(storage.base.resolvingSymlinksInPath().path + "/"))
    }

    func testMissingCourseWritesNothing() throws {
        let ok = try importer.importFile(id: "f1", courseId: "nope", folderId: nil,
                                         name: "a.pdf", contentType: "x", bytes: Data("a".utf8))
        XCTAssertFalse(ok)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.base.appendingPathComponent("nope").path))
        XCTAssertNil(try ClassFileRepository(db: db).find(id: "f1"))
    }

    func testUnsafeCourseIdWritesNothing() throws {
        let ok = try importer.importFile(id: "f1", courseId: "..", folderId: nil,
                                         name: "a.pdf", contentType: "x", bytes: Data("a".utf8))
        XCTAssertFalse(ok)
        XCTAssertNil(try ClassFileRepository(db: db).find(id: "f1"))
    }

    func testFolderFromOtherCourseIsRejected() throws {
        try ClassFolderRepository(db: db).create(ClassFolder(
            id: "fo2", courseId: "c2", parentFolderId: nil, name: "Other"))
        let ok = try importer.importFile(id: "f1", courseId: "c1", folderId: "fo2",
                                         name: "a.pdf", contentType: "x", bytes: Data("a".utf8))
        XCTAssertFalse(ok)
        XCTAssertTrue(filesOnDisk("c1").isEmpty)
        let missingFolder = try importer.importFile(id: "f1", courseId: "c1", folderId: "ghost",
                                                    name: "a.pdf", contentType: "x",
                                                    bytes: Data("a".utf8))
        XCTAssertFalse(missingFolder)
    }

    func testDuplicateIdSameCourseIsIdempotentAndKeepsBytes() throws {
        XCTAssertTrue(try importer.importFile(id: "f1", courseId: "c1", folderId: nil,
                                              name: "a.pdf", contentType: "x",
                                              bytes: Data("original".utf8)))
        let stored = try XCTUnwrap(ClassFileRepository(db: db).find(id: "f1")).storedName
        XCTAssertTrue(try importer.importFile(id: "f1", courseId: "c1", folderId: nil,
                                              name: "a.pdf", contentType: "x",
                                              bytes: Data("REPLACED".utf8)))
        let url = try storage.resolve(courseId: "c1", storedName: stored)
        XCTAssertEqual(try Data(contentsOf: url), Data("original".utf8))
        XCTAssertEqual(filesOnDisk("c1").count, 1)
    }

    func testDuplicateIdOtherCourseFailsAndWritesNothing() throws {
        XCTAssertTrue(try importer.importFile(id: "f1", courseId: "c1", folderId: nil,
                                              name: "a.pdf", contentType: "x",
                                              bytes: Data("original".utf8)))
        XCTAssertFalse(try importer.importFile(id: "f1", courseId: "c2", folderId: nil,
                                               name: "a.pdf", contentType: "x",
                                               bytes: Data("evil".utf8)))
        XCTAssertTrue(filesOnDisk("c2").isEmpty)
        XCTAssertEqual(try ClassFileRepository(db: db).find(id: "f1")?.courseId, "c1")
    }

    func testNewIdNeverReusesAnExistingStoredName() throws {
        XCTAssertTrue(try importer.importFile(id: "f1", courseId: "c1", folderId: nil,
                                              name: "a.pdf", contentType: "x",
                                              bytes: Data("first".utf8)))
        let first = try XCTUnwrap(ClassFileRepository(db: db).find(id: "f1"))
        XCTAssertTrue(try importer.importFile(id: "f2", courseId: "c1", folderId: nil,
                                              name: first.storedName, contentType: "x",
                                              bytes: Data("second".utf8)))
        let second = try XCTUnwrap(ClassFileRepository(db: db).find(id: "f2"))
        XCTAssertNotEqual(first.storedName, second.storedName)
        XCTAssertEqual(try Data(contentsOf: storage.resolve(courseId: "c1",
                                                            storedName: first.storedName)),
                       Data("first".utf8))
    }

    func testFailedInsertLeavesNoNewFile() throws {
        // Make the row insert fail after the bytes are written: a trigger that
        // aborts every class_file insert.
        try db.queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_insert BEFORE INSERT ON class_file
                BEGIN SELECT RAISE(ABORT, 'boom'); END
            """)
        }
        XCTAssertThrowsError(try importer.importFile(id: "f1", courseId: "c1", folderId: nil,
                                                     name: "a.pdf", contentType: "x",
                                                     bytes: Data("a".utf8)))
        XCTAssertTrue(filesOnDisk("c1").isEmpty)
    }

    func testExtensionIsSanitized() {
        XCTAssertEqual(ClassFileImporter.sanitizedExtension(of: "a.pdf"), "pdf")
        XCTAssertEqual(ClassFileImporter.sanitizedExtension(of: "noext"), nil)
        XCTAssertEqual(ClassFileImporter.sanitizedExtension(of: "x.tar/../evil"), nil)
        XCTAssertEqual(ClassFileImporter.sanitizedExtension(of: "a.verylongext"), nil)
        XCTAssertEqual(ClassFileImporter.sanitizedExtension(of: "a.p-f"), nil)
        XCTAssertEqual(ClassFileImporter.sanitizedExtension(of: ".hidden"), nil)
    }
}
