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

    // MARK: - A2-15: delivery is tracked separately from dismissal

    private func payload(_ id: String) -> BriefingPayload {
        BriefingPayload(id: id, kindRaw: BriefingKind.morning.rawValue,
                        title: "Morning", body: "hi", firedAt: Date(), actionables: [])
    }

    func testFailedPushIsRetriedOnceByDrain() async throws {
        let db = try InMemoryDB.make()
        let pushes = PushRecorder(results: [false, true, true])
        let dispatcher = BriefingDispatcher(
            db: db, isFocused: { false }, pushToUI: { await pushes.push($0) })

        try await dispatcher.deliver(payload("p1"))
        XCTAssertEqual(try BriefingRepository(db: db).deliveredAt(id: "p1"), nil)

        try await dispatcher.drainQueue(since: Date().addingTimeInterval(-3600))
        XCTAssertNotNil(try BriefingRepository(db: db).deliveredAt(id: "p1"))

        try await dispatcher.drainQueue(since: Date().addingTimeInterval(-3600))
        let ids = await pushes.ids
        XCTAssertEqual(ids, ["p1", "p1"], "one failed push, one successful retry, no resend")
    }

    func testSuccessfulPushIsNotResentEvenIfUndismissed() async throws {
        let db = try InMemoryDB.make()
        let pushes = PushRecorder(results: [true, true])
        let dispatcher = BriefingDispatcher(
            db: db, isFocused: { false }, pushToUI: { await pushes.push($0) })

        try await dispatcher.deliver(payload("p2"))
        try await dispatcher.drainQueue(since: Date().addingTimeInterval(-3600))

        let ids = await pushes.ids
        XCTAssertEqual(ids, ["p2"])
        XCTAssertNil(try BriefingRepository(db: db).find(id: "p2")?.dismissedAt)
    }

    func testFocusedDeliverQueuesAndDrainAfterUnfocusPushes() async throws {
        let db = try InMemoryDB.make()
        let focused = FocusFlag(true)
        let pushes = PushRecorder(results: [true])
        let dispatcher = BriefingDispatcher(
            db: db, isFocused: { focused.value }, pushToUI: { await pushes.push($0) })

        try await dispatcher.deliver(payload("p3"))
        try await dispatcher.drainQueue(since: Date().addingTimeInterval(-3600))
        var ids = await pushes.ids
        XCTAssertEqual(ids, [], "drain while focused must not push")

        focused.value = false
        try await dispatcher.drainQueue(since: Date().addingTimeInterval(-3600))
        ids = await pushes.ids
        XCTAssertEqual(ids, ["p3"])
    }
}

private actor PushRecorder {
    private var results: [Bool]
    private(set) var ids: [String] = []
    init(results: [Bool]) { self.results = results }
    func push(_ p: BriefingPayload) -> Bool {
        ids.append(p.id)
        return results.isEmpty ? true : results.removeFirst()
    }
}

private final class FocusFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ v: Bool) { _value = v }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
