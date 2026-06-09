import XCTest
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

final class AssistantCalendarBootstrapTests: XCTestCase {

    /// Marks the calendar time zone as already aligned so `ensureAssistantCalendar`
    /// skips its one-time PATCH — keeps unrelated tests deterministic.
    private func markTimeZoneAligned(_ db: AssistantDB) throws {
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)
    }

    func testCreatesCalendarIfMissing() async throws {
        let http = MockHTTPClient()
        // First call: listCalendars returns no "Assistant"
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        // Second call: createCalendar returns new id
        http.enqueueJSON(#"{"id":"new_asst_cal","summary":"Assistant"}"#)
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let db = try InMemoryDB.make()
        try markTimeZoneAligned(db)
        let boot = AssistantCalendarBootstrap(client: client, db: db)

        let id = try await boot.ensureAssistantCalendar()
        XCTAssertEqual(id, "new_asst_cal")
        XCTAssertEqual(try boot.cachedCalendarId(), "new_asst_cal")
    }

    func testReusesExistingCalendar() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"""
        { "items": [
            { "id": "asst_existing", "summary": "Assistant" },
            { "id": "primary", "summary": "My" }
        ] }
        """#)
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let db = try InMemoryDB.make()
        try markTimeZoneAligned(db)
        let boot = AssistantCalendarBootstrap(client: client, db: db)
        let id = try await boot.ensureAssistantCalendar()
        XCTAssertEqual(id, "asst_existing")
    }

    func testCachedSkipsNetwork() async throws {
        let http = MockHTTPClient()  // no responses queued
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set("gcal_assistant_calendar_id", value: "cached_id")
        try markTimeZoneAligned(db)
        let boot = AssistantCalendarBootstrap(client: client, db: db)
        XCTAssertEqual(try boot.cachedCalendarId(), "cached_id")
        let id = try await boot.ensureAssistantCalendar()
        XCTAssertEqual(id, "cached_id")
    }

    /// A calendar created without a `timeZone` defaults to UTC. The bootstrap
    /// must PATCH it to the user's zone and record that it did so.
    func testAlignsCalendarTimeZone() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)  // listCalendars
        http.enqueueJSON(#"{"id":"new_cal","summary":"Assistant"}"#)       // createCalendar
        http.enqueueJSON(#"{"id":"new_cal","summary":"Assistant"}"#)       // timeZone PATCH
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let db = try InMemoryDB.make()
        let boot = AssistantCalendarBootstrap(client: client, db: db)

        _ = try await boot.ensureAssistantCalendar()

        let tz = TimeZone.current.identifier
        XCTAssertEqual(
            try SettingRepository(db: db).get(AssistantCalendarBootstrap.timeZoneKey), tz)
        let patch = http.sentRequests.last
        XCTAssertEqual(patch?.httpMethod, "PATCH")
        let bodyObj = patch?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String]
        }
        XCTAssertEqual(bodyObj?["timeZone"], tz)
    }

    /// Once aligned, the bootstrap must not PATCH the calendar again.
    func testSkipsTimeZonePatchWhenAlreadyAligned() async throws {
        let http = MockHTTPClient()
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set("gcal_assistant_calendar_id", value: "cached_id")
        try markTimeZoneAligned(db)
        let boot = AssistantCalendarBootstrap(client: client, db: db)

        _ = try await boot.ensureAssistantCalendar()
        XCTAssertTrue(http.sentRequests.isEmpty)
    }
}
