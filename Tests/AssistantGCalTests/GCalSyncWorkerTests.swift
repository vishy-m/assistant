import XCTest
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
}
