import XCTest
@testable import AssistantGrades

final class GradingScaleTests: XCTestCase {

    private let standard: [String: Double] = [
        "A": 93, "A-": 90, "B+": 87, "B": 83, "B-": 80,
        "C+": 77, "C": 73, "C-": 70, "D+": 67, "D": 63, "D-": 60
    ]

    func testLetterForScore() {
        let s = GradingScale(cutoffs: standard)
        XCTAssertEqual(s.letter(for: 95), "A")
        XCTAssertEqual(s.letter(for: 90), "A-")
        XCTAssertEqual(s.letter(for: 89.9), "B+")
        XCTAssertEqual(s.letter(for: 0), "F")
    }

    func testMeetsTarget() {
        let s = GradingScale(cutoffs: standard)
        XCTAssertTrue(s.meetsOrExceeds(current: 91, target: "A-"))
        XCTAssertFalse(s.meetsOrExceeds(current: 89, target: "A-"))
    }
}
