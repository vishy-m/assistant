import XCTest
@testable import AssistantShared

final class CanvasHitTestingTests: XCTestCase {
    private func pin(id: String = "p", x: Double, y: Double,
                     w: Double = 100, h: Double = 60,
                     rotation: Double = 0, z: Int = 0) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: "c", fileId: "f", x: x, y: y,
                    width: w, height: h, rotation: rotation, zOrder: z)
    }

    func testPointInsideUnrotatedPin() {
        let p = pin(x: 100, y: 100)
        XCTAssertTrue(CanvasHitTesting.point(CGPoint(x: 100, y: 100), inside: p))
        XCTAssertTrue(CanvasHitTesting.point(CGPoint(x: 149, y: 129), inside: p))
        XCTAssertFalse(CanvasHitTesting.point(CGPoint(x: 151, y: 100), inside: p))
        XCTAssertFalse(CanvasHitTesting.point(CGPoint(x: 100, y: 131), inside: p))
    }

    func testRotationIsRespected() {
        // 90° rotation swaps the card's axes (100x60 -> effectively 60x100).
        // A point 40 right of center is inside unrotated (40 < half-width 50)
        // but outside at 90° (40 > half-height 30).
        let flat = pin(x: 100, y: 100)
        let rotated = pin(x: 100, y: 100, rotation: .pi / 2)
        let probe = CGPoint(x: 140, y: 100)
        XCTAssertTrue(CanvasHitTesting.point(probe, inside: flat))
        XCTAssertFalse(CanvasHitTesting.point(probe, inside: rotated))
        // And the converse: 40 above center is outside unrotated (40 > 30)
        // but inside at 90° (40 < 50).
        let probe2 = CGPoint(x: 100, y: 60)
        XCTAssertFalse(CanvasHitTesting.point(probe2, inside: flat))
        XCTAssertTrue(CanvasHitTesting.point(probe2, inside: rotated))
    }

    func testTopmostPinPrefersHigherZOrder() {
        let bottom = pin(id: "bottom", x: 0, y: 0, z: 1)
        let top = pin(id: "top", x: 10, y: 10, z: 2)
        let hit = CanvasHitTesting.topmostPin(at: CGPoint(x: 5, y: 5),
                                              in: [bottom, top]) { _ in true }
        XCTAssertEqual(hit?.id, "top")
    }

    func testTopmostPinSkipsNonMatching() {
        let bottom = pin(id: "bottom", x: 0, y: 0, z: 1)
        let top = pin(id: "top", x: 10, y: 10, z: 2)
        let hit = CanvasHitTesting.topmostPin(at: CGPoint(x: 5, y: 5),
                                              in: [bottom, top]) { $0.id == "bottom" }
        XCTAssertEqual(hit?.id, "bottom")
    }

    func testTopmostPinNilWhenNothingUnderPoint() {
        let p = pin(x: 0, y: 0)
        XCTAssertNil(CanvasHitTesting.topmostPin(at: CGPoint(x: 500, y: 500),
                                                 in: [p]) { _ in true })
    }

    func testBoundingCenterOfPins() {
        // Pin A spans x [0, 100], pin B spans x [200, 300] -> center x 150.
        let a = pin(id: "a", x: 50, y: 50, w: 100, h: 60)
        let b = pin(id: "b", x: 250, y: 250, w: 100, h: 60)
        let c = PinLayout.boundingCenter(of: [a, b])
        XCTAssertEqual(c?.x, 150)
        XCTAssertEqual(c?.y, 150)
        XCTAssertNil(PinLayout.boundingCenter(of: []))
    }
}
