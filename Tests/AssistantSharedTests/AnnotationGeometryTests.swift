import XCTest
@testable import AssistantShared

final class AnnotationGeometryTests: XCTestCase {
    func testBoundingBoxOfPoints() {
        let box = AnnotationGeometry.boundingBox(of: [[0, 0], [10, 4], [-2, 8]])
        XCTAssertEqual(box, CGRect(x: -2, y: 0, width: 12, height: 8))
        XCTAssertNil(AnnotationGeometry.boundingBox(of: []))
        // Degenerate (single point / straight horizontal line) pads to ≥ 1.
        let dot = AnnotationGeometry.boundingBox(of: [[5, 5]])!
        XCTAssertGreaterThanOrEqual(dot.width, 1)
        XCTAssertGreaterThanOrEqual(dot.height, 1)
    }

    func testPointNearPolyline() {
        let line: [[Double]] = [[0, 0], [100, 0]]
        XCTAssertTrue(AnnotationGeometry.point(CGPoint(x: 50, y: 8),
                                               isNearPolyline: line, tolerance: 10))
        XCTAssertFalse(AnnotationGeometry.point(CGPoint(x: 50, y: 12),
                                                isNearPolyline: line, tolerance: 10))
        XCTAssertFalse(AnnotationGeometry.point(CGPoint(x: 120, y: 0),
                                                isNearPolyline: line, tolerance: 10))
    }

    func testCircleIntersectsPolyline() {
        let line: [[Double]] = [[0, 0], [100, 0]]
        XCTAssertTrue(AnnotationGeometry.circle(center: CGPoint(x: 50, y: 10),
                                                radius: 12, intersectsPolyline: line))
        XCTAssertFalse(AnnotationGeometry.circle(center: CGPoint(x: 50, y: 30),
                                                 radius: 12, intersectsPolyline: line))
    }

    func testTranslateAndScalePoints() {
        let pts: [[Double]] = [[0, 0], [10, 10]]
        XCTAssertEqual(AnnotationGeometry.translate(points: pts, dx: 5, dy: -5),
                       [[5, -5], [15, 5]])
        let scaled = AnnotationGeometry.scale(points: pts,
                                              from: CGRect(x: 0, y: 0, width: 10, height: 10),
                                              to: CGRect(x: 0, y: 0, width: 20, height: 40))
        XCTAssertEqual(scaled, [[0, 0], [20, 40]])
    }

    func testLineEndpoints() {
        let box = CGRect(x: 0, y: 0, width: 10, height: 20)
        let normal = AnnotationGeometry.lineEndpoints(in: box, flipped: false)
        XCTAssertEqual(normal.a, CGPoint(x: 0, y: 0))
        XCTAssertEqual(normal.b, CGPoint(x: 10, y: 20))
        let flipped = AnnotationGeometry.lineEndpoints(in: box, flipped: true)
        XCTAssertEqual(flipped.a, CGPoint(x: 0, y: 20))
        XCTAssertEqual(flipped.b, CGPoint(x: 10, y: 0))
    }

    private func shapeDTO(_ shape: AnnotationShape, fill: String? = nil,
                          flipped: Bool = false, z: Int = 0) -> ClassAnnotationDTO {
        ClassAnnotationDTO(
            id: "s-\(shape.rawValue)-\(z)", courseId: "c1", kind: "shape",
            x: 50, y: 50, width: 100, height: 100, zOrder: z,
            payload: ClassAnnotationDTO.encodePayload(
                ShapePayload(shape: shape, strokeColor: "#000000",
                             fillColor: fill, lineWidth: 2, flipped: flipped)))
    }

    func testKindAwareHitTests() {
        // Stroke: near the polyline only.
        let stroke = ClassAnnotationDTO.stroke(id: "st", courseId: "c1",
                                               points: [[0, 0], [100, 0]],
                                               color: "#000000", lineWidth: 4, zOrder: 0)!
        XCTAssertTrue(AnnotationGeometry.point(CGPoint(x: 50, y: 5), inside: stroke, tolerance: 10))
        XCTAssertFalse(AnnotationGeometry.point(CGPoint(x: 50, y: 40), inside: stroke, tolerance: 10))
        // Unfilled rect: near border only, not deep inside.
        let rect = shapeDTO(.rect)
        XCTAssertTrue(AnnotationGeometry.point(CGPoint(x: 50, y: 2), inside: rect, tolerance: 10))
        XCTAssertFalse(AnnotationGeometry.point(CGPoint(x: 50, y: 50), inside: rect, tolerance: 10))
        // Filled rect: anywhere inside.
        XCTAssertTrue(AnnotationGeometry.point(CGPoint(x: 50, y: 50),
                                               inside: shapeDTO(.rect, fill: "#FFEE00"),
                                               tolerance: 10))
        // Line: near the diagonal.
        let line = shapeDTO(.line)
        XCTAssertTrue(AnnotationGeometry.point(CGPoint(x: 50, y: 50), inside: line, tolerance: 10))
        XCTAssertFalse(AnnotationGeometry.point(CGPoint(x: 90, y: 10), inside: line, tolerance: 10))
        // Sticky: anywhere in the box.
        let sticky = ClassAnnotationDTO(id: "n", courseId: "c1", kind: "sticky",
                                        x: 0, y: 0, width: 100, height: 100, zOrder: 0,
                                        payload: ClassAnnotationDTO.encodePayload(
                                            StickyPayload(text: "", color: "yellow")))
        XCTAssertTrue(AnnotationGeometry.point(CGPoint(x: 10, y: 10), inside: sticky, tolerance: 10))
        // Malformed payload: never hit, never crash.
        let broken = ClassAnnotationDTO(id: "b", courseId: "c1", kind: "shape",
                                        x: 50, y: 50, width: 100, height: 100,
                                        zOrder: 0, payload: "garbage")
        XCTAssertFalse(AnnotationGeometry.point(CGPoint(x: 50, y: 2), inside: broken, tolerance: 10))
    }

    func testTopmostInkPrefersHigherZOrderAndSkipsObjects() {
        let bottom = shapeDTO(.rect, fill: "#FFFFFF", z: 1)
        let top = shapeDTO(.rect, fill: "#000000", z: 2)
        let sticky = ClassAnnotationDTO(id: "n", courseId: "c1", kind: "sticky",
                                        x: 50, y: 50, width: 100, height: 100, zOrder: 9,
                                        payload: ClassAnnotationDTO.encodePayload(
                                            StickyPayload(text: "", color: "yellow")))
        let hit = AnnotationGeometry.topmostInk(at: CGPoint(x: 50, y: 50),
                                                in: [bottom, top, sticky], tolerance: 10)
        XCTAssertEqual(hit?.id, top.id)  // sticky ignored despite zOrder 9
        XCTAssertNil(AnnotationGeometry.topmostInk(at: CGPoint(x: 500, y: 500),
                                                   in: [bottom, top], tolerance: 10))
    }

    func testStrokeFactoryComputesBBoxAndRejectsDots() {
        let s = ClassAnnotationDTO.stroke(id: "s", courseId: "c1",
                                          points: [[0, 0], [10, 20]],
                                          color: "#111111", lineWidth: 2, zOrder: 7)!
        XCTAssertEqual(s.x, 5); XCTAssertEqual(s.y, 10)
        XCTAssertEqual(s.width, 10); XCTAssertEqual(s.height, 20)
        XCTAssertEqual(s.zOrder, 7)
        XCTAssertEqual(s.decodedPayload(StrokePayload.self)?.points, [[0, 0], [10, 20]])
        XCTAssertNil(ClassAnnotationDTO.stroke(id: "d", courseId: "c1", points: [[1, 1]],
                                               color: "#111111", lineWidth: 2, zOrder: 0))
    }
}
