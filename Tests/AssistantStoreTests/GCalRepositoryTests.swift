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

    // MARK: - W3: (calendar_id, gcal_event_id) identity

    private func row(_ id: String, cal: String, start: Date, minutes: Double = 60,
                     recurring: String? = nil) -> GCalEventCache {
        GCalEventCache(gcalEventId: id, calendarId: cal, title: "\(cal)/\(id)",
                       startAt: start, endAt: start.addingTimeInterval(minutes * 60),
                       location: nil, category: "Misc", lastSyncedAt: Date(),
                       rawJson: "{}", recurringEventId: recurring)
    }

    func testSameEventIdOnTwoCalendarsKeepsBothRows() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try repo.upsert(row("ev", cal: "a", start: t))
        try repo.upsert(row("ev", cal: "b", start: t))

        XCTAssertEqual(try repo.find(calendarId: "a", eventId: "ev")?.title, "a/ev")
        XCTAssertEqual(try repo.find(calendarId: "b", eventId: "ev")?.title, "b/ev")
        // Unscoped lookup is ambiguous → fails closed.
        XCTAssertNil(try repo.find(id: "ev"))
        try repo.deleteCached(id: "ev")
        XCTAssertNotNil(try repo.find(calendarId: "a", eventId: "ev"))

        try repo.deleteCached(calendarId: "a", eventId: "ev")
        XCTAssertNil(try repo.find(calendarId: "a", eventId: "ev"))
        XCTAssertNotNil(try repo.find(calendarId: "b", eventId: "ev"))
        // Now unique again → unscoped lookup works.
        XCTAssertEqual(try repo.find(id: "ev")?.calendarId, "b")
    }

    func testScopedSeriesDeleteLeavesOtherCalendar() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try repo.upsert(row("m_1", cal: "a", start: t, recurring: "m"))
        try repo.upsert(row("m_1", cal: "b", start: t, recurring: "m"))
        try repo.upsert(row("m_2", cal: "b", start: t + 86_400, recurring: "m"))

        try repo.deleteCachedSeries(calendarId: "a", recurringEventId: "m")
        XCTAssertNil(try repo.find(calendarId: "a", eventId: "m_1"))
        XCTAssertNotNil(try repo.find(calendarId: "b", eventId: "m_1"))
        XCTAssertNotNil(try repo.find(calendarId: "b", eventId: "m_2"))
    }

    func testEventsOverlappingIsHalfOpen() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        let s = Date(timeIntervalSince1970: 1_800_000_000)
        let e = s + 3600 * 5
        try repo.upsert(row("before", cal: "a", start: s - 3600))          // ends at s
        try repo.upsert(row("straddle", cal: "a", start: s - 1800))        // ends inside
        try repo.upsert(row("inside", cal: "a", start: s + 3600))
        try repo.upsert(row("atEnd", cal: "a", start: e))                  // starts at end
        let ids = try repo.eventsOverlapping(start: s, end: e).map(\.gcalEventId)
        XCTAssertEqual(ids, ["straddle", "inside"])
    }

    func testReplaceWindowDeletesMissingRowsOnlyInsideWindowForThatCalendar() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        let s = Date(timeIntervalSince1970: 1_800_000_000)
        let e = s + 86_400 * 10
        try repo.upsert(row("gone", cal: "a", start: s + 3600))
        try repo.upsert(row("kept", cal: "a", start: s + 7200))
        try repo.upsert(row("outside", cal: "a", start: e + 3600))
        try repo.upsert(row("gone", cal: "b", start: s + 3600))
        try repo.replaceWindow(calendarId: "a", start: s, end: e,
                               upserts: [row("kept", cal: "a", start: s + 9000),
                                         row("new", cal: "a", start: s + 9000)],
                               deletes: [])
        XCTAssertNil(try repo.find(calendarId: "a", eventId: "gone"))
        XCTAssertEqual(try repo.find(calendarId: "a", eventId: "kept")?.startAt, s + 9000)
        XCTAssertNotNil(try repo.find(calendarId: "a", eventId: "new"))
        XCTAssertNotNil(try repo.find(calendarId: "a", eventId: "outside"))
        XCTAssertNotNil(try repo.find(calendarId: "b", eventId: "gone"))
    }

    func testDeadLetterAndPayloadUpdate() throws {
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.enqueue(PendingGCalOp(
            id: "op1", opType: "insert_event", payloadJson: "{}",
            attempts: 0, lastAttemptAt: nil, createdAt: Date()))
        try repo.updateOpPayload(id: "op1", payloadJson: #"{"x":1}"#)
        XCTAssertEqual(try repo.pendingOps().first?.payloadJson, #"{"x":1}"#)
    }
}
