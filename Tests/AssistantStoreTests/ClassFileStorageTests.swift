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
}
