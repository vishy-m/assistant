import XCTest
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM
import AssistantShared

final class CalendarWriterTests: XCTestCase {

    private func makeWriter(http: MockHTTPClient, db: AssistantDB,
                            online: Bool) -> CalendarWriter {
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        return CalendarWriter(client: client, db: db, isOnline: { online })
    }

    func testCreateOnlineInsertsAndCaches() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)
        let writer = makeWriter(http: http, db: db, online: true)

        let result = try await writer.create(
            title: "Study", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil, description: nil)

        XCTAssertEqual(result.id, "ev_created_1")
        XCTAssertNotNil(try GCalRepository(db: db).find(id: "ev_created_1"))
    }

    func testCreateOfflineEnqueuesOutbox() async throws {
        let http = MockHTTPClient()
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        let writer = makeWriter(http: http, db: db, online: false)

        _ = try? await writer.create(
            title: "Study", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil, description: nil)

        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 1)
    }

    func testDeleteRemovesFromCache() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("{}")
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "e1", calendarId: "cal1", title: "X",
            startAt: Date(), endAt: Date(), location: nil, category: "generic",
            lastSyncedAt: Date(), rawJson: "{}"))
        let writer = makeWriter(http: http, db: db, online: true)

        try await writer.delete(eventId: "e1")
        XCTAssertNil(try repo.find(id: "e1"))
    }

    func testDeleteOfMissingGoogleEventStillClearsCache() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("{}", status: 404)   // Google: event already gone
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "stale", calendarId: "cal1", title: "Phantom",
            startAt: Date(), endAt: Date(), location: nil, category: "generic",
            lastSyncedAt: Date(), rawJson: "{}"))
        let writer = makeWriter(http: http, db: db, online: true)

        try await writer.delete(eventId: "stale")
        XCTAssertNil(try repo.find(id: "stale"))
    }

    func testCreateSetsColorIdFromCategory() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)
        let writer = makeWriter(http: http, db: db, online: true)

        _ = try await writer.create(
            title: "Final", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil,
            description: nil, category: "Exam")

        let body = http.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertNotNil(body?["colorId"])
    }

    func testCreateUnknownCategoryFallsBackToDefault() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)
        let writer = makeWriter(http: http, db: db, online: true)

        let result = try await writer.create(
            title: "Thing", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil,
            description: nil, category: "DoesNotExist")

        XCTAssertEqual(result.category, "Misc")
    }

    func testRecurringCreateSendsRruleAndSkipsCache() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)
        let writer = makeWriter(http: http, db: db, online: true)

        let rule = RecurrenceRule(frequency: .weekly, interval: 1,
                                  byWeekday: [2], untilDate: nil, count: 4)
        let result = try await writer.create(
            title: "Standup", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil,
            description: nil, category: "Misc", recurrence: rule)

        // The Google body carried the RRULE...
        let body = http.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let rec = body?["recurrence"] as? [String]
        XCTAssertEqual(rec, ["RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4"])
        // ...the result is flagged recurring...
        XCTAssertTrue(result.isRecurring)
        // ...and the master is NOT cached (instances arrive via sync instead).
        XCTAssertNil(try GCalRepository(db: db).find(id: "ev_created_1"))
    }

    func testRecurringCreateOfflineThrows() async throws {
        let http = MockHTTPClient()
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        let writer = makeWriter(http: http, db: db, online: false)
        let rule = RecurrenceRule(frequency: .daily, interval: 1,
                                  byWeekday: [], untilDate: nil, count: nil)
        do {
            _ = try await writer.create(
                title: "X", start: Date(timeIntervalSince1970: 1000),
                end: Date(timeIntervalSince1970: 4600), location: nil,
                description: nil, category: "Misc", recurrence: rule)
            XCTFail("expected offline recurring create to throw")
        } catch {}
        XCTAssertEqual(http.sentRequests.count, 0)
    }

    func testDeleteRecurringInstanceDeletesSeries() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("{}")  // Google DELETE of the master
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        // Two cached instances of one series.
        for stamp in ["a", "b"] {
            try repo.upsert(GCalEventCache(
                gcalEventId: "master1_\(stamp)", calendarId: "cal1", title: "Standup",
                startAt: Date(), endAt: Date(), location: nil, category: "Misc",
                lastSyncedAt: Date(), rawJson: "{}", recurringEventId: "master1"))
        }
        let writer = makeWriter(http: http, db: db, online: true)

        try await writer.delete(eventId: "master1_a")

        // Google DELETE targeted the master id, and all local rows are gone.
        XCTAssertTrue(http.sentRequests.last?.url?.path.hasSuffix("/events/master1") ?? false)
        XCTAssertNil(try repo.find(id: "master1_a"))
        XCTAssertNil(try repo.find(id: "master1_b"))
    }
}
