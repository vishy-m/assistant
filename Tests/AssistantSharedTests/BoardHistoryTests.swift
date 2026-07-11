import XCTest
@testable import AssistantShared

final class BoardHistoryTests: XCTestCase {
    private func annOp(_ n: Int) -> BoardOp {
        .annotation(before: nil,
                    after: ClassAnnotationDTO(id: "a\(n)", courseId: "c", kind: "sticky",
                                              x: 0, y: 0, width: 1, height: 1,
                                              zOrder: n, payload: "{}"))
    }

    func testRecordUndoRedoRoundTrip() {
        var h = BoardHistory()
        XCTAssertFalse(h.canUndo); XCTAssertFalse(h.canRedo)
        h.record(annOp(1))
        XCTAssertTrue(h.canUndo)
        let op = h.undo()
        XCTAssertEqual(op, annOp(1))
        XCTAssertFalse(h.canUndo); XCTAssertTrue(h.canRedo)
        XCTAssertEqual(h.redo(), annOp(1))
        XCTAssertTrue(h.canUndo); XCTAssertFalse(h.canRedo)
    }

    func testUndoRedoOrderIsLIFO() {
        var h = BoardHistory()
        h.record(annOp(1)); h.record(annOp(2))
        XCTAssertEqual(h.undo(), annOp(2))
        XCTAssertEqual(h.undo(), annOp(1))
        XCTAssertEqual(h.redo(), annOp(1))
        XCTAssertEqual(h.redo(), annOp(2))
        XCTAssertNil(h.redo())
    }

    func testNewRecordClearsRedo() {
        var h = BoardHistory()
        h.record(annOp(1)); _ = h.undo()
        h.record(annOp(2))
        XCTAssertFalse(h.canRedo)
        XCTAssertEqual(h.undo(), annOp(2))
    }

    func testCapEvictsOldest() {
        var h = BoardHistory()
        for n in 1...(BoardHistory.cap + 10) { h.record(annOp(n)) }
        var popped: [BoardOp] = []
        while let op = h.undo() { popped.append(op) }
        XCTAssertEqual(popped.count, BoardHistory.cap)
        XCTAssertEqual(popped.first, annOp(BoardHistory.cap + 10))
        XCTAssertEqual(popped.last, annOp(11))  // 1...10 evicted
    }

    func testClearEmptiesBothStacks() {
        var h = BoardHistory()
        h.record(annOp(1)); h.record(annOp(2)); _ = h.undo()
        h.clear()
        XCTAssertFalse(h.canUndo); XCTAssertFalse(h.canRedo)
        XCTAssertNil(h.undo()); XCTAssertNil(h.redo())
    }

    func testPinOpsCarrySnapshots() {
        let before = ClassPinDTO(id: "p", courseId: "c", fileId: "f", x: 0, y: 0,
                                 width: 10, height: 10, rotation: 0, zOrder: 0)
        let after = ClassPinDTO(id: "p", courseId: "c", fileId: "f", x: 5, y: 5,
                                width: 10, height: 10, rotation: 0, zOrder: 0)
        var h = BoardHistory()
        h.record(.pin(before: before, after: after))
        guard case let .pin(b, a)? = h.undo() else { return XCTFail("expected pin op") }
        XCTAssertEqual(b, before); XCTAssertEqual(a, after)
    }

    func testBatchIsOneUndoUnit() {
        var h = BoardHistory()
        h.record(.batch([annOp(1), annOp(2), annOp(3)]))
        XCTAssertTrue(h.canUndo)
        guard case let .batch(ops)? = h.undo() else { return XCTFail("expected batch") }
        XCTAssertEqual(ops, [annOp(1), annOp(2), annOp(3)])
        XCTAssertFalse(h.canUndo)   // one unit, not three
        XCTAssertTrue(h.canRedo)
        XCTAssertEqual(h.redo(), .batch([annOp(1), annOp(2), annOp(3)]))
    }
}
