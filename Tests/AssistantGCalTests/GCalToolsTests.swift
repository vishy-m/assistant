import XCTest
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

final class GCalToolsTests: XCTestCase {

    func testCreateEventOnlineGoesToAPI() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "asst_cal")
        // Calendar time zone already aligned — skip the one-time PATCH.
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)

        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        var registry = ToolRegistry()
        GCalTools.register(into: &registry, client: client, db: db,
                           isOnline: { true })

        let result = try await registry.invoke(
            name: "create_calendar_event",
            argumentsJSON: #"""
            {"summary":"Study OS","start":"2026-05-14T16:00:00Z","end":"2026-05-14T18:00:00Z"}
            """#)
        XCTAssertTrue(result.contains("ev_created_1"))
    }

    func testCreateEventOfflineEnqueuesOutbox() async throws {
        let http = MockHTTPClient()
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "asst_cal")

        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        var registry = ToolRegistry()
        GCalTools.register(into: &registry, client: client, db: db,
                           isOnline: { false })

        let result = try await registry.invoke(
            name: "create_calendar_event",
            argumentsJSON: #"""
            {"summary":"Study","start":"2026-05-14T16:00:00Z","end":"2026-05-14T18:00:00Z"}
            """#)
        XCTAssertTrue(result.contains("not_confirmed"))
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 1)
    }

    func testListCalendarFromCache() async throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        let start = Date()
        try repo.upsert(GCalEventCache(
            gcalEventId: "ev1", calendarId: "primary", title: "Lecture",
            startAt: start, endAt: start.addingTimeInterval(3600),
            location: nil, category: "class", lastSyncedAt: Date(), rawJson: "{}"))

        let http = MockHTTPClient()
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        var registry = ToolRegistry()
        GCalTools.register(into: &registry, client: client, db: db, isOnline: { true })

        let result = try await registry.invoke(name: "list_calendar",
                                               argumentsJSON: #"{"range":"today"}"#)
        XCTAssertTrue(result.contains("Lecture"))
    }
}
