import XCTest
@testable import AssistantShared

final class ClassAnnotationDTOTests: XCTestCase {
    private func dto(kind: String, payload: String) -> ClassAnnotationDTO {
        ClassAnnotationDTO(id: "a1", courseId: "c1", kind: kind,
                           x: 10, y: 20, width: 100, height: 50, zOrder: 3,
                           payload: payload)
    }

    func testAllPayloadKindsRoundTrip() {
        let stroke = StrokePayload(points: [[0, 0], [10, 5.5]], color: "#1D1D1F", lineWidth: 4)
        let shape = ShapePayload(shape: .arrow, strokeColor: "#E5484D",
                                 fillColor: nil, lineWidth: 2, flipped: true)
        let sticky = StickyPayload(text: "hi", color: "yellow")
        let text = TextPayload(text: "note", fontSize: 20, color: "#2E90FA")

        XCTAssertEqual(dto(kind: "stroke", payload: ClassAnnotationDTO.encodePayload(stroke))
            .decodedPayload(StrokePayload.self), stroke)
        XCTAssertEqual(dto(kind: "shape", payload: ClassAnnotationDTO.encodePayload(shape))
            .decodedPayload(ShapePayload.self), shape)
        XCTAssertEqual(dto(kind: "sticky", payload: ClassAnnotationDTO.encodePayload(sticky))
            .decodedPayload(StickyPayload.self), sticky)
        XCTAssertEqual(dto(kind: "text", payload: ClassAnnotationDTO.encodePayload(text))
            .decodedPayload(TextPayload.self), text)
    }

    func testMalformedPayloadDecodesToNilNotCrash() {
        XCTAssertNil(dto(kind: "stroke", payload: "not json").decodedPayload(StrokePayload.self))
        XCTAssertNil(dto(kind: "stroke", payload: "{}").decodedPayload(StrokePayload.self))
    }

    func testUnknownKindIsNil() {
        XCTAssertNil(dto(kind: "hologram", payload: "{}").annotationKind)
        XCTAssertEqual(dto(kind: "sticky", payload: "{}").annotationKind, .sticky)
    }

    func testBoxIsCenteredRect() {
        let b = dto(kind: "text", payload: "{}").box
        XCTAssertEqual(b, CGRect(x: -40, y: -5, width: 100, height: 50))
    }

    func testCopyHelpersChangeOnlyTheirFields() {
        let d = dto(kind: "sticky", payload: "{}")
        let moved = d.moved(x: 99, y: 98)
        XCTAssertEqual(moved.x, 99); XCTAssertEqual(moved.y, 98)
        XCTAssertEqual(moved.width, d.width); XCTAssertEqual(moved.payload, d.payload)
        let resized = d.resized(width: 7, height: 8)
        XCTAssertEqual(resized.width, 7); XCTAssertEqual(resized.height, 8)
        XCTAssertEqual(resized.x, d.x)
        let repayloaded = d.withPayload("{\"a\":1}")
        XCTAssertEqual(repayloaded.payload, "{\"a\":1}")
        XCTAssertEqual(repayloaded.id, d.id)
    }

    func testDTOJSONRoundTrip() throws {
        let d = dto(kind: "stroke",
                    payload: ClassAnnotationDTO.encodePayload(
                        StrokePayload(points: [[1, 2]], color: "#000000", lineWidth: 2)))
        let back = try JSONDecoder().decode(ClassAnnotationDTO.self,
                                            from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
