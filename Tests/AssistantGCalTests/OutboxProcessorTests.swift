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

    // MARK: - W3: id replay (A2-03) and dead-letter (NEW-03)

    private func stage(_ db: AssistantDB, _ payload: InsertEventPayload,
                       attempts: Int = 0) throws {
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "asst_cal")
        let json = String(data: try JSONEncoder().encode(OutboxPayload.insertEvent(payload)),
                          encoding: .utf8)!
        try GCalRepository(db: db).enqueue(PendingGCalOp(
            id: "op1", opType: "insert_event", payloadJson: json,
            attempts: attempts, lastAttemptAt: nil, createdAt: Date()))
    }

    private func processor(_ http: MockHTTPClient, _ db: AssistantDB) -> OutboxProcessor {
        OutboxProcessor(client: GCalClient(http: http, accessTokenProvider: { "atk" }),
                        db: db, quota: QuotaGuard(db: db, cap: 100))
    }

    private func sentId(_ r: URLRequest?) -> String? {
        r?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["id"]
            as? String
    }

    private func payload(id: String?) -> InsertEventPayload {
        InsertEventPayload(summary: "S", startISO: "2026-05-14T16:00:00Z",
                           endISO: "2026-05-14T18:00:00Z", location: nil, description: nil,
                           eventId: id, category: "Exam")
    }

    func testReplaySendsStoredIdAndCategory() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try stage(db, payload(id: "0123456789abcdefghijklmnopqrstuv"))
        try await processor(http, db).drainOnce()
        XCTAssertEqual(sentId(http.sentRequests.first), "0123456789abcdefghijklmnopqrstuv")
        let body = http.sentRequests.first?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let priv = (body?["extendedProperties"] as? [String: Any])?["private"] as? [String: Any]
        XCTAssertEqual(priv?["assistant_category"] as? String, "Exam")
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 0)
    }

    func testReplayConflictConfirmsWithGetAndRemovesOp() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":409}}"#, status: 409)
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try stage(db, payload(id: "abcde12345"))
        try await processor(http, db).drainOnce()
        XCTAssertEqual(http.sentRequests.count, 2)
        XCTAssertEqual(http.sentRequests[1].httpMethod, "GET")
        XCTAssertEqual(http.sentRequests[1].url?.path,
                       "/calendar/v3/calendars/asst_cal/events/abcde12345")
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 0)
    }

    func testLegacyPayloadWithoutIdGetsStableIdPersisted() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":500}}"#, status: 500)
        let db = try InMemoryDB.make()
        try stage(db, InsertEventPayload(summary: "S", startISO: "2026-05-14T16:00:00Z",
                                         endISO: "2026-05-14T18:00:00Z",
                                         location: nil, description: nil))
        try await processor(http, db).drainOnce()
        let op = try XCTUnwrap(try GCalRepository(db: db).pendingOps().first)
        guard case .insertEvent(let p) = try JSONDecoder().decode(
            OutboxPayload.self, from: op.payloadJson.data(using: .utf8)!) else { return XCTFail() }
        XCTAssertNotNil(p.eventId)
        XCTAssertEqual(sentId(http.sentRequests.first), p.eventId)
    }

    func testPermanentFailureDeadLettersAfterEightAttempts() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":403}}"#, status: 403)
        let db = try InMemoryDB.make()
        try stage(db, payload(id: "abcde12345"), attempts: 7)
        try await processor(http, db).drainOnce()
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 0)
        try await processor(http, db).drainOnce()
        XCTAssertEqual(http.sentRequests.count, 1)
    }

    func testPermanentFailureBelowCapIsRetried() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":403}}"#, status: 403)
        let db = try InMemoryDB.make()
        try stage(db, payload(id: "abcde12345"), attempts: 0)
        try await processor(http, db).drainOnce()
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().first?.attempts, 1)
    }

    func testOldPayloadJsonStillDecodes() throws {
        let json = #"{"insertEvent":{"_0":{"summary":"S","startISO":"a","endISO":"b"}}}"#
        let p = try JSONDecoder().decode(OutboxPayload.self, from: json.data(using: .utf8)!)
        guard case .insertEvent(let ins) = p else { return XCTFail() }
        XCTAssertNil(ins.eventId)
        XCTAssertNil(ins.category)
    }

    // MARK: - W9: category patch (A2-09 follow-up)

    private func stagePatch(_ db: AssistantDB) throws {
        let payload = OutboxPayload.patchEventCategory(PatchEventCategoryPayload(
            calendarId: "asst_cal", eventId: "e1", category: "Exam", colorId: "4"))
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        try GCalRepository(db: db).enqueue(PendingGCalOp(
            id: "op-patch", opType: "patch_event_category", payloadJson: json,
            attempts: 0, lastAttemptAt: nil, createdAt: Date()))
    }

    func testPatchCategorySendsAssistantCategory() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try stagePatch(db)
        try await processor(http, db).drainOnce()
        XCTAssertEqual(http.sentRequests.first?.httpMethod, "PATCH")
        XCTAssertEqual(http.sentRequests.first?.url?.path,
                       "/calendar/v3/calendars/asst_cal/events/e1")
        let body = http.sentRequests.first?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let priv = (body?["extendedProperties"] as? [String: Any])?["private"] as? [String: Any]
        XCTAssertEqual(priv?["assistant_category"] as? String, "Exam")
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 0)
    }

    func testPatchCategoryFailureIsRetriedNotDropped() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"error":{"code":500}}"#, status: 500)
        let db = try InMemoryDB.make()
        try stagePatch(db)
        try await processor(http, db).drainOnce()
        let remaining = try GCalRepository(db: db).pendingOps()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.attempts, 1)
        XCTAssertEqual(remaining.first?.id, "op-patch")
    }
}
