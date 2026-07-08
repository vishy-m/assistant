import XCTest
@testable import AssistantShared

final class CanvasViewportTests: XCTestCase {
    func testIdentityViewportRoundTrips() {
        let v = CanvasViewport()
        let p = CGPoint(x: 123, y: -456)
        XCTAssertEqual(v.worldToScreen(p), p)
        XCTAssertEqual(v.screenToWorld(p), p)
    }

    func testWorldToScreenAppliesZoomThenOffset() {
        let v = CanvasViewport(offsetX: 10, offsetY: 20, zoom: 2)
        XCTAssertEqual(v.worldToScreen(CGPoint(x: 5, y: 7)), CGPoint(x: 20, y: 34))
    }

    func testScreenToWorldInvertsWorldToScreen() {
        let v = CanvasViewport(offsetX: -300, offsetY: 42, zoom: 0.5)
        let world = CGPoint(x: 87, y: -1000)
        let back = v.screenToWorld(v.worldToScreen(world))
        XCTAssertEqual(back.x, world.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, world.y, accuracy: 1e-9)
    }

    func testPannedTranslatesOffset() {
        let v = CanvasViewport(offsetX: 10, offsetY: 10, zoom: 2)
            .panned(byScreenDeltaX: 5, deltaY: -3)
        XCTAssertEqual(v.offsetX, 15)
        XCTAssertEqual(v.offsetY, 7)
        XCTAssertEqual(v.zoom, 2)
    }

    func testZoomAtAnchorKeepsAnchorStationary() {
        let v = CanvasViewport(offsetX: 40, offsetY: -25, zoom: 1)
        let anchor = CGPoint(x: 200, y: 150)
        let worldUnderAnchor = v.screenToWorld(anchor)
        let zoomed = v.zoomed(by: 1.5, at: anchor)
        let after = zoomed.worldToScreen(worldUnderAnchor)
        XCTAssertEqual(after.x, anchor.x, accuracy: 1e-9)
        XCTAssertEqual(after.y, anchor.y, accuracy: 1e-9)
        XCTAssertEqual(zoomed.zoom, 1.5, accuracy: 1e-9)
    }

    func testZoomClampsToBounds() {
        let v = CanvasViewport()
        XCTAssertEqual(v.zoomed(by: 100, at: .zero).zoom, CanvasViewport.maxZoom)
        XCTAssertEqual(v.zoomed(by: 0.001, at: .zero).zoom, CanvasViewport.minZoom)
    }

    func testNonFiniteAndNonPositiveInputsAreRejected() {
        let v = CanvasViewport(offsetX: 1, offsetY: 2, zoom: 2)
        XCTAssertEqual(v.zoomed(by: .nan, at: .zero), v)
        XCTAssertEqual(v.zoomed(by: 0, at: .zero), v)
        XCTAssertEqual(v.zoomed(by: -1, at: .zero), v)
        XCTAssertEqual(v.panned(byScreenDeltaX: .nan, deltaY: 1), v)
        XCTAssertEqual(v.zoomed(by: 1.5, at: CGPoint(x: CGFloat.nan, y: 0)), v)
        XCTAssertEqual(v.zoomed(by: 1.5, at: CGPoint(x: 0, y: CGFloat.infinity)), v)
        let bad = CanvasViewport(offsetX: .infinity, offsetY: .nan, zoom: .nan)
        XCTAssertEqual(bad, CanvasViewport())
    }

    func testCenteredPutsWorldPointAtCanvasCenter() {
        let v = CanvasViewport.centered(onWorldX: 500, worldY: -200,
                                        canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(v.zoom, 1)
        XCTAssertEqual(v.worldToScreen(CGPoint(x: 500, y: -200)),
                       CGPoint(x: 400, y: 300))
    }

    func testDecodingClampsOutOfRangeZoom() throws {
        let json = #"{"offsetX": 5, "offsetY": 6, "zoom": 100}"#.data(using: .utf8)!
        let v = try JSONDecoder().decode(CanvasViewport.self, from: json)
        XCTAssertEqual(v.zoom, CanvasViewport.maxZoom)
        XCTAssertEqual(v.offsetX, 5)
    }

    func testEncodeDecodeRoundTrip() throws {
        let v = CanvasViewport(offsetX: -12.5, offsetY: 900, zoom: 0.75)
        let data = try JSONEncoder().encode(v)
        XCTAssertEqual(try JSONDecoder().decode(CanvasViewport.self, from: data), v)
    }
}
