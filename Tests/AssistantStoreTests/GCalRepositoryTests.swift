import XCTest
@testable import AssistantStore

final class GCalRepositoryTests: XCTestCase {

    func testUpsertCachedEvent() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let e = GCalEventCache(
            gcalEventId: "ev1", calendarId: "primary", title: "Lecture",
            startAt: start, endAt: end, location: nil, category: "class",
            lastSyncedAt: Date(), rawJson: "{}")
        try repo.upsert(e)
        try repo.upsert(GCalEventCache(
            gcalEventId: "ev1", calendarId: "primary", title: "Lecture (updated)",
            startAt: start, endAt: end, location: "Room 1", category: "class",
            lastSyncedAt: Date(), rawJson: "{}"))

        XCTAssertEqual(try repo.find(id: "ev1")?.title, "Lecture (updated)")
        XCTAssertEqual(try repo.eventsOn(date: start).count, 1)
    }

    func testOutboxQueueAndDrain() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.enqueue(PendingGCalOp(
            id: "op1", opType: "insert_event", payloadJson: "{}",
            attempts: 0, lastAttemptAt: nil, createdAt: Date()))
        XCTAssertEqual(try repo.pendingOps().count, 1)

        try repo.removeOp(id: "op1")
        XCTAssertEqual(try repo.pendingOps().count, 0)
    }
}
