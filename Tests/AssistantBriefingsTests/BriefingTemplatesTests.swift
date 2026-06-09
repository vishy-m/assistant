import XCTest
@testable import AssistantBriefings

final class BriefingTemplatesTests: XCTestCase {

    func testMorningHasItems() {
        let text = BriefingTemplates.morning(items: ["OS lecture 10am", "HW1 due 5pm"])
        XCTAssertTrue(text.contains("OS lecture"))
        XCTAssertTrue(text.contains("HW1"))
    }

    func testEmptyMorning() {
        let text = BriefingTemplates.morning(items: [])
        XCTAssertTrue(text.lowercased().contains("nothing"))
    }

    func testPreEvent() {
        let text = BriefingTemplates.preEvent(title: "OS exam", minutesUntil: 15)
        XCTAssertTrue(text.contains("OS exam"))
        XCTAssertTrue(text.contains("15"))
    }
}
