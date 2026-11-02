import XCTest
import GRDB
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

final class GCalSyncWorkerTests: XCTestCase {

    func testInitialSyncPopulatesCache() async throws {
        let http = MockHTTPClient()
        // listCalendars
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        // listEvents (no syncToken yet) → returns one event + nextSyncToken
        http.enqueueJSON(GCalFixtures.eventsList)

        let db = try InMemoryDB.make()
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let worker = GCalSyncWorker(client: client, db: db,
                                    quota: QuotaGuard(db: db, cap: 100),
                                    clock: { Date() })
        try await worker.runOnce()

        let repo = GCalRepository(db: db)
        XCTAssertNotNil(try repo.find(id: "ev1"))
        XCTAssertEqual(try SyncState(db: db).syncToken(for: "primary"), "TOK_NEXT")
    }

    func testSyncTokenInvalidClearsAndRetries() async throws {
        let http = MockHTTPClient()
        // listCalendars
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        // First incremental list with old token → 410
        http.enqueueJSON(#"{"error":{"errors":[{"reason":"fullSyncRequired"}]}}"#, status: 410)
        // Full re-sync → success
        http.enqueueJSON(GCalFixtures.eventsList)

        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "OLD")
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let worker = GCalSyncWorker(client: client, db: db,
                                    quota: QuotaGuard(db: db, cap: 100))
        try await worker.runOnce()
        XCTAssertEqual(try SyncState(db: db).syncToken(for: "primary"), "TOK_NEXT")
    }

    func testSyncCapturesRecurringEventId() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(GCalFixtures.recurringInstancesList)

        let db = try InMemoryDB.make()
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let worker = GCalSyncWorker(client: client, db: db,
                                    quota: QuotaGuard(db: db, cap: 100))
        try await worker.runOnce()

        let cached = try GCalRepository(db: db).find(id: "master1_20260514T140000Z")
        XCTAssertEqual(cached?.recurringEventId, "master1")
    }

    func testQuotaExhaustedSkipsSilently() async throws {
        let http = MockHTTPClient()  // no responses needed; quota blocks first call
        let db = try InMemoryDB.make()
        // Manually consume quota
        let quota = QuotaGuard(db: db, cap: 1)
        _ = try quota.tryConsume()
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let worker = GCalSyncWorker(client: client, db: db, quota: quota)

        try await worker.runOnce()
        // No HTTP call should have happened
        XCTAssertEqual(http.sentRequests.count, 0)
    }

    // MARK: - W3 helpers

    private func cacheRow(_ db: AssistantDB, id: String, calendarId: String = "primary",
                          title: String = "Old", start: Date, minutes: Double = 60,
                          category: String = "Misc") throws {
        try GCalRepository(db: db).upsert(GCalEventCache(
            gcalEventId: id, calendarId: calendarId, title: title,
            startAt: start, endAt: start.addingTimeInterval(minutes * 60),
            location: nil, category: category, lastSyncedAt: Date(), rawJson: "{}"))
    }

    private static let iso = ISO8601DateFormatter()
    private static let fixedNow = iso.date(from: "2026-05-13T12:00:00Z")!

    private func makeWorker(_ http: MockHTTPClient, _ db: AssistantDB,
                            clock: @escaping @Sendable () -> Date = { GCalSyncWorkerTests.fixedNow })
        -> GCalSyncWorker {
        GCalSyncWorker(client: GCalClient(http: http, accessTokenProvider: { "atk" }),
                       db: db, quota: QuotaGuard(db: db, cap: 1000), clock: clock)
    }

    private func rows(_ db: AssistantDB, id: String) throws -> [GCalEventCache] {
        try db.queue.read { db in
            try GCalEventCache.filter(Column("gcal_event_id") == id).fetchAll(db)
        }
    }

    // MARK: - A2-06 cancelled events

    func testCancelledEventWithDatesDeletesCachedRow() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"""
        { "items": [ { "id": "ev1", "status": "cancelled", "summary": "OS Lecture",
            "start": { "dateTime": "2026-05-14T10:00:00-04:00" },
            "end":   { "dateTime": "2026-05-14T11:30:00-04:00" } } ],
          "nextSyncToken": "TOK2" }
        """#)
        http.enqueueJSON(#"{"items":[]}"#)   // possible horizon fill
        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "TOK1")
        try cacheRow(db, id: "ev1", start: Self.iso.date(from: "2026-05-14T14:00:00Z")!)

        try await makeWorker(http, db).runOnce()
        XCTAssertTrue(try rows(db, id: "ev1").isEmpty)
    }

    func testCancelledEventWithoutDatesStillDeletes() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"{"items":[{"id":"ev1","status":"cancelled"}],"nextSyncToken":"TOK2"}"#)
        http.enqueueJSON(#"{"items":[]}"#)
        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "TOK1")
        try cacheRow(db, id: "ev1", start: Self.iso.date(from: "2026-05-14T14:00:00Z")!)

        try await makeWorker(http, db).runOnce()
        XCTAssertTrue(try rows(db, id: "ev1").isEmpty)
    }

    // MARK: - A2-07 all-day events

    func testAllDayEventIsCachedAtLocalMidnightsAndReplacesTimedRow() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"""
        { "items": [ { "id": "ev1", "summary": "Holiday",
            "start": { "date": "2026-11-02", "timeZone": "America/Chicago" },
            "end":   { "date": "2026-11-03", "timeZone": "America/Chicago" } } ],
          "nextSyncToken": "TOK2" }
        """#)
        http.enqueueJSON(#"{"items":[]}"#)
        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "TOK1")
        // Previously a timed 10:00–11:00 event.
        try cacheRow(db, id: "ev1", start: Self.iso.date(from: "2026-11-02T16:00:00Z")!)

        try await makeWorker(http, db).runOnce()
        let r = try rows(db, id: "ev1")
        XCTAssertEqual(r.count, 1)
        // Chicago is UTC-6 on 2026-11-02 (CST after the Nov 1 DST end).
        XCTAssertEqual(r.first?.startAt, Self.iso.date(from: "2026-11-02T06:00:00Z"))
        XCTAssertEqual(r.first?.endAt, Self.iso.date(from: "2026-11-03T06:00:00Z"))
        XCTAssertEqual(r.first?.title, "Holiday")
        XCTAssertTrue(r.first?.rawJson.contains("\"allDay\":true") ?? false)
    }

    // MARK: - A2-09 category preservation

    func testSyncKeepsLocalCategory() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"""
        { "items": [
          { "id": "ev1", "summary": "Midterm (moved)",
            "start": { "dateTime": "2026-05-14T12:00:00Z" },
            "end":   { "dateTime": "2026-05-14T13:00:00Z" } },
          { "id": "ev2", "summary": "Brand new",
            "start": { "dateTime": "2026-05-15T12:00:00Z" },
            "end":   { "dateTime": "2026-05-15T13:00:00Z" } },
          { "id": "ev3", "summary": "Rebuilt",
            "extendedProperties": { "private": { "assistant_category": "Club" } },
            "start": { "dateTime": "2026-05-16T12:00:00Z" },
            "end":   { "dateTime": "2026-05-16T13:00:00Z" } } ],
          "nextSyncToken": "TOK2" }
        """#)
        http.enqueueJSON(#"{"items":[]}"#)
        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "TOK1")
        try cacheRow(db, id: "ev1", title: "Midterm",
                     start: Self.iso.date(from: "2026-05-14T10:00:00Z")!, category: "Exam")

        try await makeWorker(http, db).runOnce()
        let r = try rows(db, id: "ev1").first
        XCTAssertEqual(r?.category, "Exam")
        XCTAssertEqual(r?.title, "Midterm (moved)")
        XCTAssertEqual(r?.startAt, Self.iso.date(from: "2026-05-14T12:00:00Z"))
        XCTAssertEqual(try rows(db, id: "ev2").first?.category, "Misc")
        XCTAssertEqual(try rows(db, id: "ev3").first?.category, "Club")
    }

    // MARK: - A2-05 410 full re-sync

    func testSyncTokenInvalidRemovesInWindowRowsMissingFromSnapshot() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"{"error":{"errors":[{"reason":"fullSyncRequired"}]}}"#, status: 410)
        http.enqueueJSON(GCalFixtures.eventsList)
        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "OLD")
        try cacheRow(db, id: "ev-old", start: Self.iso.date(from: "2026-05-20T10:00:00Z")!)
        // Outside the window (beyond now+60d): must survive.
        try cacheRow(db, id: "ev-far", start: Self.iso.date(from: "2026-09-01T10:00:00Z")!)
        // Same window, other calendar: must survive.
        try cacheRow(db, id: "ev-other", calendarId: "other",
                     start: Self.iso.date(from: "2026-05-20T10:00:00Z")!)

        try await makeWorker(http, db).runOnce()
        XCTAssertTrue(try rows(db, id: "ev-old").isEmpty)
        XCTAssertEqual(try rows(db, id: "ev1").count, 1)
        XCTAssertEqual(try rows(db, id: "ev-far").count, 1)
        XCTAssertEqual(try rows(db, id: "ev-other").count, 1)
        XCTAssertEqual(try SyncState(db: db).syncToken(for: "primary"), "TOK_NEXT")
    }

    func testFailedFullResyncLeavesCacheAndTokenUntouched() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"{"error":{"errors":[{"reason":"fullSyncRequired"}]}}"#, status: 410)
        http.enqueueJSON(#"""
        { "items": [ { "id": "ev1", "summary": "New",
            "start": { "dateTime": "2026-05-14T12:00:00Z" },
            "end":   { "dateTime": "2026-05-14T13:00:00Z" } } ],
          "nextPageToken": "P2" }
        """#)
        http.enqueueJSON(#"{"error":{"code":500}}"#, status: 500)
        let db = try InMemoryDB.make()
        try SyncState(db: db).setSyncToken("primary", token: "OLD")
        try cacheRow(db, id: "ev-old", start: Self.iso.date(from: "2026-05-20T10:00:00Z")!)

        do { try await makeWorker(http, db).runOnce(); XCTFail("expected server error") }
        catch GCalError.server(500) {}
        XCTAssertEqual(try rows(db, id: "ev-old").count, 1)
        XCTAssertTrue(try rows(db, id: "ev1").isEmpty)
        XCTAssertEqual(try SyncState(db: db).syncToken(for: "primary"), "OLD")
    }

    // MARK: - A2-08 horizon gap fill

    func testHorizonAdvancesWithoutReplacingIncrementalToken() async throws {
        final class Clock: @unchecked Sendable {
            private let lock = NSLock(); private var t: Date
            init(_ t: Date) { self.t = t }
            func now() -> Date { lock.lock(); defer { lock.unlock() }; return t }
            func advance(days: Double) { lock.lock(); t += days * 86_400; lock.unlock() }
        }
        let clock = Clock(Self.fixedNow)
        let http = MockHTTPClient()
        // Run 1: full sync, nothing in window.
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"{"items":[],"nextSyncToken":"T1"}"#)
        // Run 2 (50 days later): empty incremental, then gap fill holds ev-far.
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON(#"{"items":[],"nextSyncToken":"T2"}"#)
        http.enqueueJSON(#"""
        { "items": [ { "id": "ev-far", "summary": "Far",
            "start": { "dateTime": "2026-07-20T12:00:00Z" },
            "end":   { "dateTime": "2026-07-20T13:00:00Z" } } ],
          "nextSyncToken": "GAP" }
        """#)
        let db = try InMemoryDB.make()
        let worker = makeWorker(http, db, clock: { clock.now() })

        try await worker.runOnce()
        let firstMax = URLComponents(url: http.sentRequests[1].url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "timeMax" }?.value
        XCTAssertNotNil(firstMax)
        clock.advance(days: 50)
        try await worker.runOnce()

        XCTAssertEqual(http.sentRequests.count, 5)
        guard http.sentRequests.count == 5 else { return }
        let gap = URLComponents(url: http.sentRequests[4].url!, resolvingAgainstBaseURL: false)!
        let items = gap.queryItems ?? []
        XCTAssertNil(items.first { $0.name == "syncToken" })
        XCTAssertEqual(items.first { $0.name == "timeMin" }?.value, firstMax)
        XCTAssertEqual(try rows(db, id: "ev-far").count, 1)
        XCTAssertEqual(try SyncState(db: db).syncToken(for: "primary"), "T2")
    }
}
