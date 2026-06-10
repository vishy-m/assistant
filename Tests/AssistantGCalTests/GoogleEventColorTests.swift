import XCTest
@testable import AssistantGCal

final class GoogleEventColorTests: XCTestCase {

    func testExactPaletteColorsMapToTheirOwnId() {
        XCTAssertEqual(GoogleEventColor.nearestColorId(toHex: "D50000"), "11") // Tomato
        XCTAssertEqual(GoogleEventColor.nearestColorId(toHex: "33B679"), "2")  // Sage
        XCTAssertEqual(GoogleEventColor.nearestColorId(toHex: "039BE5"), "7")  // Peacock
    }

    func testNearMatchSnapsToClosest() {
        XCTAssertEqual(GoogleEventColor.nearestColorId(toHex: "D20303"), "11")
        XCTAssertEqual(GoogleEventColor.nearestColorId(toHex: "#616161"), "8")
    }

    func testPaletteHasElevenColors() {
        XCTAssertEqual(GoogleEventColor.palette.count, 11)
    }
}
