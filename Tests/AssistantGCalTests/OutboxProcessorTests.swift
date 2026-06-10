import XCTest
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

final class OutboxProcessorTests: XCTestCase {

    func testDrainSuccessRemovesOp() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)

        // Pre-stage an Assistant calendar id
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey,
                                          value: "asst_cal")

        let payload = OutboxPayload.insertEvent(InsertEventPayload(
            summary: "Study", startISO: "2026-05-14T16:00:00Z", endISO: "2026-05-14T18:00:00Z",
            location: nil, description: nil))
        let payloadData = try JSONEncoder().encode(payload)
        let payloadJSON = String(data: payloadData, encoding: .utf8)!
        try repo.enqueue(PendingGCalOp(
            id: "op1", opType: "insert_event", payloadJson: payloadJSON,
            attempts: 0, lastAttemptAt: nil, createdAt: Date()))

        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let processor = OutboxProcessor(client: client, db: db,
                                        quota: QuotaGuard(db: db, cap: 100))
        try await processor.drainOnce()

        XCTAssertEqual(try repo.pendingOps().count, 0)
    }

    func testFailureKeepsOpAndIncrementsAttempts() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":500}}"#, status: 500)
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey,
                                          value: "asst_cal")
        let payload = OutboxPayload.insertEvent(InsertEventPayload(
            summary: "X", startISO: "2026-05-14T16:00:00Z", endISO: "2026-05-14T18:00:00Z",
            location: nil, description: nil))
        let payloadJSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        try repo.enqueue(PendingGCalOp(
            id: "op1", opType: "insert_event", payloadJson: payloadJSON,
            attempts: 0, lastAttemptAt: nil, createdAt: Date()))

        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let processor = OutboxProcessor(client: client, db: db,
                                        quota: QuotaGuard(db: db, cap: 100))
        try await processor.drainOnce()

        let remaining = try repo.pendingOps()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.attempts, 1)
    }
}
