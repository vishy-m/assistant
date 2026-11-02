import XCTest
@testable import AssistantShared

final class ClassLoadGateTests: XCTestCase {
    func testReplyForPreviousCourseIsDropped() {
        var gate = ClassLoadGate()
        let a = gate.start(courseId: "A")
        let b = gate.start(courseId: "B")
        XCTAssertFalse(gate.accepts(a))
        XCTAssertTrue(gate.accepts(b))
    }

    func testSwitchBackAcceptsOnlyLatestLoad() {
        var gate = ClassLoadGate()
        let a1 = gate.start(courseId: "A")
        _ = gate.start(courseId: "B")
        let a2 = gate.start(courseId: "A")
        XCTAssertFalse(gate.accepts(a1))
        XCTAssertTrue(gate.accepts(a2))
    }

    func testCurrentTokenMatchesLatestStart() {
        var gate = ClassLoadGate()
        XCTAssertNil(gate.current)
        let a = gate.start(courseId: "A")
        XCTAssertEqual(gate.current, a)
        XCTAssertEqual(gate.current?.courseId, "A")
    }
}
