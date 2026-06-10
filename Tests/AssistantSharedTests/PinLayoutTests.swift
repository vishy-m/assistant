import XCTest
@testable import AssistantShared

final class PinLayoutTests: XCTestCase {
    private func pin(_ id: String, z: Int) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: "c1", fileId: "f1", x: 0, y: 0,
                    width: 10, height: 10, rotation: 0, zOrder: z)
    }

    func testNextZOrderIsZeroWhenEmpty() {
        XCTAssertEqual(PinLayout.nextZOrder([]), 0)
    }

    func testNextZOrderIsMaxPlusOne() {
        XCTAssertEqual(PinLayout.nextZOrder([pin("a", z: 0), pin("b", z: 4), pin("c", z: 2)]), 5)
    }

    func testMakePinCentersAtPointWithDefaultSize() {
        let p = PinLayout.makePin(id: "p1", courseId: "c1", fileId: "f1",
                                  x: 120, y: 250, zOrder: 3)
        XCTAssertEqual(p.x, 120)
        XCTAssertEqual(p.y, 250)
        XCTAssertEqual(p.width, PinLayout.defaultWidth)
        XCTAssertEqual(p.height, PinLayout.defaultHeight)
        XCTAssertEqual(p.rotation, 0)
        XCTAssertEqual(p.zOrder, 3)
        XCTAssertEqual(p.fileId, "f1")
        XCTAssertEqual(p.courseId, "c1")
        XCTAssertEqual(p.id, "p1")
    }
}
