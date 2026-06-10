import XCTest
@testable import AssistantGCal
@testable import AssistantLLM   // MockHTTPClient

final class GCalClientTests: XCTestCase {

    private func makeClient(_ http: MockHTTPClient, token: String = "atk") -> GCalClient {
        GCalClient(http: http, accessTokenProvider: { token })
    }

    func testListCalendars() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.calendarList)
        let client = makeClient(http)
        let list = try await client.listCalendars()
        XCTAssertEqual(list.items.count, 2)
        // Verify auth header
        XCTAssertEqual(http.sentRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer atk")
    }

    func testListEventsWithSyncTokenSends410Triggers() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":410,"message":"Sync token is no longer valid","errors":[{"reason":"fullSyncRequired"}]}}"#, status: 410)
        let client = makeClient(http)
        do {
            _ = try await client.listEvents(calendarId: "primary", syncToken: "OLD")
            XCTFail("expected")
        } catch GCalError.syncTokenInvalid {} catch { XCTFail("\(error)") }
    }

    func testInsertEventInAssistantCalendar() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let client = makeClient(http)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(3600)
        let ev = try await client.insertEvent(
            calendarId: "calX", summary: "Study OS",
            start: start, end: end, location: nil, description: nil)
        XCTAssertEqual(ev.id, "ev_created_1")
        XCTAssertEqual(http.sentRequests.first?.url?.path, "/calendar/v3/calendars/calX/events")
    }

    func testCreateCalendar() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"id":"new_cal_1","summary":"Assistant"}"#)
        let client = makeClient(http)
        let cal = try await client.createCalendar(summary: "Assistant")
        XCTAssertEqual(cal.id, "new_cal_1")
    }

    func testUnauthorizedThrows() async {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":401}}"#, status: 401)
        let client = makeClient(http)
        do {
            _ = try await client.listCalendars()
            XCTFail()
        } catch GCalError.unauthorized {} catch { XCTFail("\(error)") }
    }
}
