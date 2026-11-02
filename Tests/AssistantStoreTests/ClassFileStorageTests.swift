import XCTest
@testable import AssistantStore

final class ClassFileStorageTests: XCTestCase {
    private func tempBase() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClassFilesTest-\(UUID().uuidString)")
    }

    func testWriteThenReadAndRemove() throws {
        let storage = ClassFileStorage(base: tempBase())
        let data = Data("hello".utf8)
        let url = try storage.write(data, courseId: "c1", storedName: "f1.txt")
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(storage.fileURL(courseId: "c1", storedName: "f1.txt").path, url.path)
        try storage.remove(courseId: "c1", storedName: "f1.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRemoveMissingFileDoesNotThrow() throws {
        let storage = ClassFileStorage(base: tempBase())
        XCTAssertNoThrow(try storage.remove(courseId: "c1", storedName: "nope.txt"))
    }

    // MARK: - Containment (A1 #2 / A3-01)

    /// A sandbox dir holding `base` plus a sentinel file next to it, so an
    /// escape out of `base` would hit the sentinel.
    private func sandbox() throws -> (root: URL, storage: ClassFileStorage, sentinel: URL) {
        let root = tempBase()
        let base = root.appendingPathComponent("Assistant/ClassFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("Assistant/assistant.sqlite")
        try Data("original".utf8).write(to: sentinel)
        return (root, ClassFileStorage(base: base), sentinel)
    }

    func testUnsafeCourseIdsAreRejectedAndNothingOutsideBaseChanges() throws {
        let (root, storage, sentinel) = try sandbox()
        for courseId in ["..", "foo/bar", "c/../../..", ".", "", "a\0b"] {
            XCTAssertThrowsError(try storage.write(Data("evil".utf8), courseId: courseId,
                                                   storedName: "assistant.sqlite"), courseId)
            XCTAssertThrowsError(try storage.remove(courseId: courseId,
                                                    storedName: "assistant.sqlite"), courseId)
            XCTAssertThrowsError(try storage.resolve(courseId: courseId, storedName: "x"), courseId)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.base.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("foo").path))
    }

    func testUnsafeStoredNamesAreRejected() throws {
        let (_, storage, sentinel) = try sandbox()
        for name in ["../x", "..", ".", "", "foo/../../x", "a/b", "../../assistant.sqlite",
                     "/abs", "back\\slash", "nul\0byte"] {
            XCTAssertThrowsError(try storage.write(Data("evil".utf8), courseId: "c1",
                                                   storedName: name), name)
            XCTAssertThrowsError(try storage.remove(courseId: "c1", storedName: name), name)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
        // The rejected write must not have created the course dir either.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.base.appendingPathComponent("c1").path))
    }

    func testSymlinkedCourseDirIsRejected() throws {
        let (root, storage, sentinel) = try sandbox()
        // Course dir that is really a symlink pointing out of base.
        try FileManager.default.createSymbolicLink(
            at: storage.base.appendingPathComponent("linked"),
            withDestinationURL: root.appendingPathComponent("Assistant"))
        XCTAssertThrowsError(try storage.write(Data("evil".utf8), courseId: "linked",
                                               storedName: "assistant.sqlite"))
        XCTAssertThrowsError(try storage.remove(courseId: "linked", storedName: "assistant.sqlite"))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
    }

    func testResolvedPathSitsUnderBase() throws {
        let storage = ClassFileStorage(base: tempBase())
        let url = try storage.write(Data("x".utf8), courseId: "c1", storedName: "f.pdf")
        let real = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path
        let realBase = storage.base.resolvingSymlinksInPath().path
        XCTAssertTrue(real.hasPrefix(realBase + "/"), "\(real) not under \(realBase)")
    }

    // MARK: - Exclusive create (A1 #5)

    func testWriteNewNeverOverwrites() throws {
        let storage = ClassFileStorage(base: tempBase())
        try storage.writeNew(Data("first".utf8), courseId: "c1", storedName: "f.pdf")
        XCTAssertThrowsError(try storage.writeNew(Data("second".utf8), courseId: "c1",
                                                  storedName: "f.pdf"))
        let url = try storage.resolve(courseId: "c1", storedName: "f.pdf")
        XCTAssertEqual(try Data(contentsOf: url), Data("first".utf8))
    }

    // MARK: - Cleanup helpers (A3-04 / A3-07)

    func testDiscardTreatsUnsafeNamesAsGoneAndRemovesRealFiles() throws {
        let (_, storage, sentinel) = try sandbox()
        try storage.write(Data("x".utf8), courseId: "c1", storedName: "f.pdf")
        XCTAssertTrue(storage.discard(courseId: "c1", storedName: "f.pdf"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try storage.resolve(courseId: "c1", storedName: "f.pdf").path))
        // Unsafe legacy names can never address bytes under base: "gone", no touch.
        XCTAssertTrue(storage.discard(courseId: "..", storedName: "assistant.sqlite"))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
        // Missing file counts as gone.
        XCTAssertTrue(storage.discard(courseId: "c1", storedName: "missing.pdf"))
    }

    func testRemoveCourseDirectory() throws {
        let (_, storage, sentinel) = try sandbox()
        try storage.write(Data("x".utf8), courseId: "c1", storedName: "f.pdf")
        try storage.removeCourseDirectory(courseId: "c1")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.base.appendingPathComponent("c1").path))
        XCTAssertNoThrow(try storage.removeCourseDirectory(courseId: "c1")) // missing = ok
        XCTAssertThrowsError(try storage.removeCourseDirectory(courseId: ".."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.base.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
    }
}
