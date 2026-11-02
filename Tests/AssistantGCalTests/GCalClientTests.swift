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

    // MARK: - W3

    func testListCalendarsFollowsNextPageToken() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"a","summary":"A"}],"nextPageToken":"P2"}"#)
        http.enqueueJSON(#"{"items":[{"id":"b","summary":"B"}]}"#)
        let list = try await makeClient(http).listCalendars()
        XCTAssertEqual(list.items.map(\.id), ["a", "b"])
        XCTAssertEqual(http.sentRequests.count, 2)
        let q = URLComponents(url: http.sentRequests[1].url!, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        XCTAssertEqual(q.first { $0.name == "pageToken" }?.value, "P2")
    }

    func testListCalendarsStopsAtPageCap() async throws {
        let http = MockHTTPClient()
        for _ in 0..<30 { http.enqueueJSON(#"{"items":[],"nextPageToken":"SAME"}"#) }
        _ = try await makeClient(http).listCalendars()
        XCTAssertEqual(http.sentRequests.count, GCalClient.maxCalendarListPages)
    }

    func testInsertEventSendsClientId() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        _ = try await makeClient(http).insertEvent(
            eventId: "abc123def456", calendarId: "calX", summary: "S",
            start: Date(), end: Date() + 60, location: nil, description: nil)
        let body = http.sentRequests.first?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(body?["id"] as? String, "abc123def456")
    }

    func testConflictMapsTo409AndGetEventFetches() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":409}}"#, status: 409)
        http.enqueueJSON(GCalFixtures.createdEvent)
        let client = makeClient(http)
        do {
            _ = try await client.insertEvent(eventId: "x1234", calendarId: "c", summary: "S",
                                             start: Date(), end: Date(), location: nil,
                                             description: nil)
            XCTFail("expected conflict")
        } catch GCalError.conflict {}
        let ev = try await client.getEvent(calendarId: "c", eventId: "ev_created_1")
        XCTAssertEqual(ev.id, "ev_created_1")
        XCTAssertEqual(http.sentRequests.last?.httpMethod, "GET")
        XCTAssertEqual(http.sentRequests.last?.url?.path,
                       "/calendar/v3/calendars/c/events/ev_created_1")
    }
}
