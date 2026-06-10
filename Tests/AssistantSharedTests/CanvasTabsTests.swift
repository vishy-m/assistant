import XCTest
@testable import AssistantShared

final class CanvasTabsTests: XCTestCase {
    func testOpenAppendsAndActivates() {
        var t = CanvasTabs()
        t.open("a")
        XCTAssertEqual(t.openFileIds, ["a"])
        XCTAssertEqual(t.activeFileId, "a")
        XCTAssertFalse(t.isBoardActive)
    }

    func testOpenExistingFocusesWithoutDuplicating() {
        var t = CanvasTabs(openFileIds: ["a", "b"], activeFileId: "a")
        t.open("b")
        XCTAssertEqual(t.openFileIds, ["a", "b"])
        XCTAssertEqual(t.activeFileId, "b")
    }

    func testCloseActiveFallsBackToPreviousTab() {
        var t = CanvasTabs(openFileIds: ["a", "b", "c"], activeFileId: "c")
        t.close("c")
        XCTAssertEqual(t.openFileIds, ["a", "b"])
        XCTAssertEqual(t.activeFileId, "b")
    }

    func testCloseActiveFirstTabFallsBackToNewFirst() {
        var t = CanvasTabs(openFileIds: ["a", "b"], activeFileId: "a")
        t.close("a")
        XCTAssertEqual(t.openFileIds, ["b"])
        XCTAssertEqual(t.activeFileId, "b")
    }

    func testCloseLastTabActivatesBoard() {
        var t = CanvasTabs(openFileIds: ["a"], activeFileId: "a")
        t.close("a")
        XCTAssertTrue(t.openFileIds.isEmpty)
        XCTAssertNil(t.activeFileId)
        XCTAssertTrue(t.isBoardActive)
    }

    func testCloseNonActiveKeepsActive() {
        var t = CanvasTabs(openFileIds: ["a", "b"], activeFileId: "b")
        t.close("a")
        XCTAssertEqual(t.openFileIds, ["b"])
        XCTAssertEqual(t.activeFileId, "b")
    }

    func testSelectFileOnlyIfOpen_andSelectBoard() {
        var t = CanvasTabs(openFileIds: ["a"], activeFileId: "a")
        t.selectFile("zzz")
        XCTAssertEqual(t.activeFileId, "a")
        t.selectBoard()
        XCTAssertNil(t.activeFileId)
        t.selectFile("a")
        XCTAssertEqual(t.activeFileId, "a")
    }

    func testPruneRemovesMissingAndResetsActive() {
        var t = CanvasTabs(openFileIds: ["a", "b", "c"], activeFileId: "c")
        t.prune(toExisting: ["a", "b"])
        XCTAssertEqual(t.openFileIds, ["a", "b"])
        XCTAssertNil(t.activeFileId)
    }

    func testPruneKeepsActiveWhenStillPresent() {
        var t = CanvasTabs(openFileIds: ["a", "b"], activeFileId: "a")
        t.prune(toExisting: ["a"])
        XCTAssertEqual(t.openFileIds, ["a"])
        XCTAssertEqual(t.activeFileId, "a")
    }

    func testCodableRoundTrip() throws {
        let t = CanvasTabs(openFileIds: ["a", "b"], activeFileId: "b")
        let decoded = try JSONDecoder().decode(
            CanvasTabs.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(decoded, t)
    }
}
