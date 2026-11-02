import XCTest
@testable import AssistantShared

final class SplitDragMathTests: XCTestCase {

    func testSuccessiveTranslationsStayAbsoluteFromOrigin() {
        let range: ClosedRange<CGFloat> = 150...360
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 5, range: range, sign: 1), 205)
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 10, range: range, sign: 1), 210)
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 15, range: range, sign: 1), 215)
    }

    func testNegativeSignAndClampFollowThePointer() {
        let range: ClosedRange<CGFloat> = 150...360
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 30, range: range, sign: -1), 170)
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 500, range: range, sign: 1), 360)
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 20, range: range, sign: 1), 220)
        XCTAssertEqual(SplitDragMath.apply(origin: 200, translation: 80, range: range, sign: -1), 150)
    }
}
