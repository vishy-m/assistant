import XCTest
@testable import AssistantBriefings
@testable import AssistantShared
@testable import AssistantStore

final class BriefingDispatcherTests: XCTestCase {

    func testDeliversWhenNotFocused() async throws {
        let db = try InMemoryDB.make()
        var pushed: BriefingPayload?
        let dispatcher = BriefingDispatcher(
            db: db,
            isFocused: { false },
            pushToUI: { payload in pushed = payload; return true }
        )
        let payload = BriefingPayload(
            id: "b1", kindRaw: BriefingKind.morning.rawValue,
            title: "Morning", body: "hi", firedAt: Date(),
            actionables: [.init(kind: .dismiss, label: "Dismiss", payload: nil)])
        try await dispatcher.deliver(payload)

        XCTAssertEqual(pushed?.id, "b1")
        XCTAssertEqual(try BriefingRepository(db: db).recent(kind: "morning", limit: 5).count, 1)
    }

    func testQueuedWhenFocused() async throws {
        let db = try InMemoryDB.make()
        var pushed: BriefingPayload?
        let dispatcher = BriefingDispatcher(
            db: db,
            isFocused: { true },
            pushToUI: { payload in pushed = payload; return true })

        let payload = BriefingPayload(
            id: "b2", kindRaw: BriefingKind.evening.rawValue,
            title: "Evening", body: "bye", firedAt: Date(),
            actionables: [])
        try await dispatcher.deliver(payload)

        XCTAssertNil(pushed)
        // Still logged
        XCTAssertEqual(try BriefingRepository(db: db).recent(kind: "evening", limit: 5).count, 1)
    }

    func testDrainSendsQueuedAfterFocusEnds() async throws {
        let db = try InMemoryDB.make()
        var pushedIDs: [String] = []

        // Pre-stage a queued (un-dismissed) briefing
        try BriefingRepository(db: db).insert(.init(
            id: "queued1", kind: "morning", firedAt: Date(),
            payloadJson: #"{"id":"queued1","kindRaw":"morning","title":"x","body":"y","firedAt":\#(Date().timeIntervalSince1970),"actionables":[]}"#,
            dismissedAt: nil, actedOn: false))

        let dispatcher = BriefingDispatcher(
            db: db,
            isFocused: { false },
            pushToUI: { payload in pushedIDs.append(payload.id); return true })
        try await dispatcher.drainQueue(since: Date().addingTimeInterval(-3600))

        XCTAssertEqual(pushedIDs, ["queued1"])
    }
}
