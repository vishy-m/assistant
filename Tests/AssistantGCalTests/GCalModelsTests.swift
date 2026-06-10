import XCTest
@testable import AssistantGCal

final class GCalModelsTests: XCTestCase {

    func testCalendarListDecodes() throws {
        let data = GCalFixtures.calendarList.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(GCalCalendarList.self, from: data)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items.first?.id, "primary")
        XCTAssertTrue(list.items.first?.primary == true)
    }

    func testEventsListDecodes() throws {
        let data = GCalFixtures.eventsList.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(GCalEventList.self, from: data)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.nextSyncToken, "TOK_NEXT")
        XCTAssertEqual(list.items.first?.summary, "OS Lecture")
        XCTAssertNotNil(list.items.first?.start?.dateTime)
    }
}
