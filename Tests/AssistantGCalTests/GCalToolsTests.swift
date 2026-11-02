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

    // MARK: - W3: list_calendar ranges (A2-10 / A1 NEW-1)

    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d,
                                                   hour: h, minute: mi))!
    }

    /// Monday 2026-11-02 18:00 local.
    private var monday1800: Date { local(2026, 11, 2, 18) }

    private func listTitles(range: String, events: [(String, Date, Date)],
                            now: Date) async throws -> (titles: [String], raw: String) {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        for (i, (title, s, e)) in events.enumerated() {
            try repo.upsert(GCalEventCache(
                gcalEventId: "ev\(i)", calendarId: "primary", title: title,
                startAt: s, endAt: e, location: nil, category: "Misc",
                lastSyncedAt: Date(), rawJson: "{}"))
        }
        let client = GCalClient(http: MockHTTPClient(), accessTokenProvider: { "atk" })
        var registry = ToolRegistry()
        GCalTools.register(into: &registry, client: client, db: db,
                           isOnline: { true }, now: { now })
        let raw = try await registry.invoke(name: "list_calendar",
                                            argumentsJSON: #"{"range":"\#(range)"}"#)
        struct Out: Decodable { struct I: Decodable { let title: String }; let events: [I]? }
        let out = try JSONDecoder().decode(Out.self, from: raw.data(using: .utf8)!)
        return ((out.events ?? []).map(\.title), raw)
    }

    func testThisWeekCoversTheNextSevenDays() async throws {
        let h: TimeInterval = 3600
        let (titles, _) = try await listTitles(range: "this_week", events: [
            ("tuesday", local(2026, 11, 3, 10), local(2026, 11, 3, 11)),
            ("sunday-late", local(2026, 11, 8, 22), local(2026, 11, 8, 23)),
            ("day-eight", local(2026, 11, 9, 1), local(2026, 11, 9, 1) + h),
            ("monday-after-next", local(2026, 11, 16, 10), local(2026, 11, 16, 11)),
            ("multi-day", local(2026, 11, 3, 20), local(2026, 11, 5, 10)),
        ], now: monday1800)
        XCTAssertEqual(Set(titles), ["tuesday", "sunday-late", "multi-day"])
        XCTAssertEqual(titles.filter { $0 == "multi-day" }.count, 1)
    }

    func testNext24hIsARollingWindowFromNow() async throws {
        let (titles, _) = try await listTitles(range: "next_24h", events: [
            ("ended-this-morning", local(2026, 11, 2, 8), local(2026, 11, 2, 9)),
            ("in-progress", local(2026, 11, 2, 17), local(2026, 11, 2, 19)),
            ("tomorrow-9am", local(2026, 11, 3, 9), local(2026, 11, 3, 10)),
            ("now-plus-26h", local(2026, 11, 3, 20), local(2026, 11, 3, 21)),
        ], now: monday1800)
        XCTAssertEqual(titles, ["in-progress", "tomorrow-9am"])
    }

    func testTodayIsTheCivilDay() async throws {
        let (titles, _) = try await listTitles(range: "today", events: [
            ("this-morning", local(2026, 11, 2, 8), local(2026, 11, 2, 9)),
            ("tomorrow", local(2026, 11, 3, 9), local(2026, 11, 3, 10)),
        ], now: monday1800)
        XCTAssertEqual(titles, ["this-morning"])
    }

    func testUnsupportedRangeReturnsError() async throws {
        let (_, raw) = try await listTitles(range: "next_year", events: [], now: monday1800)
        XCTAssertTrue(raw.contains("unsupported range"), raw)
    }
}
