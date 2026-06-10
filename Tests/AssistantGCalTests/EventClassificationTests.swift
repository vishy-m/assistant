import XCTest
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM
import AssistantShared

final class EventClassificationTests: XCTestCase {

    private func makeWriter(http: MockHTTPClient, db: AssistantDB) -> CalendarWriter {
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        return CalendarWriter(client: client, db: db, isOnline: { true })
    }

    func testCreateWithClassWritesExtendedPropsAndTypeColor() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(GCalFixtures.createdEvent)
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.timeZoneKey,
                                          value: TimeZone.current.identifier)
        let writer = makeWriter(http: http, db: db)

        let result = try await writer.create(
            title: "Office Hours", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil, description: nil,
            category: "Misc", recurrence: nil,
            courseId: "course1", eventType: "office_hours")

        // Body carried type color (Google colorId "2") and private extended props.
        let body = http.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(body?["colorId"] as? String, "2")
        let ext = (body?["extendedProperties"] as? [String: Any])?["private"] as? [String: String]
        XCTAssertEqual(ext?["assistant_course_id"], "course1")
        XCTAssertEqual(ext?["assistant_event_type"], "office_hours")

        // Result + cache row carry the classification.
        XCTAssertEqual(result.courseId, "course1")
        XCTAssertEqual(result.eventType, "office_hours")
        let cached = try GCalRepository(db: db).find(id: "ev_created_1")
        XCTAssertEqual(cached?.courseId, "course1")
        XCTAssertEqual(cached?.eventType, "office_hours")
    }

    func testSyncReadsExtendedPropsIntoCache() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON(#"{"items":[{"id":"primary","summary":"My"}]}"#)
        http.enqueueJSON("""
        {
          "items": [
            { "id": "ev_oh",
              "summary": "OS Office Hours",
              "start": { "dateTime": "2026-05-14T10:00:00-04:00" },
              "end":   { "dateTime": "2026-05-14T11:00:00-04:00" },
              "extendedProperties": {
                "private": { "assistant_course_id": "course1", "assistant_event_type": "office_hours" }
              } }
          ],
          "nextSyncToken": "TOK1"
        }
        """)
        let db = try InMemoryDB.make()
        let client = GCalClient(http: http, accessTokenProvider: { "atk" })
        let worker = GCalSyncWorker(client: client, db: db,
                                    quota: QuotaGuard(db: db, cap: 100))
        try await worker.runOnce()

        let cached = try GCalRepository(db: db).find(id: "ev_oh")
        XCTAssertEqual(cached?.courseId, "course1")
        XCTAssertEqual(cached?.eventType, "office_hours")
    }

    func testUpdateClassificationPatchesGoogleAndCache() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {"id":"e1","summary":"OS","colorId":"3",
         "start":{"dateTime":"2026-05-14T10:00:00-04:00"},
         "end":{"dateTime":"2026-05-14T11:00:00-04:00"}}
        """)
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "e1", calendarId: "cal1", title: "OS",
            startAt: Date(), endAt: Date(), location: nil, category: "Misc",
            lastSyncedAt: Date(), rawJson: "{}"))
        let writer = makeWriter(http: http, db: db)

        try await writer.updateClassification(eventId: "e1",
                                              courseId: "course1", eventType: "discussion")

        // PATCH body carried type color (Google colorId "3") + extended props.
        let body = http.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(body?["colorId"] as? String, "3")
        let ext = (body?["extendedProperties"] as? [String: Any])?["private"] as? [String: String]
        XCTAssertEqual(ext?["assistant_event_type"], "discussion")
        XCTAssertEqual(ext?["assistant_course_id"], "course1")

        let cached = try repo.find(id: "e1")
        XCTAssertEqual(cached?.courseId, "course1")
        XCTAssertEqual(cached?.eventType, "discussion")
    }

    func testUpdateClassificationToNilClearsExtendedProps() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {"id":"e1","summary":"OS",
         "start":{"dateTime":"2026-05-14T10:00:00-04:00"},
         "end":{"dateTime":"2026-05-14T11:00:00-04:00"}}
        """)
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "e1", calendarId: "cal1", title: "OS",
            startAt: Date(), endAt: Date(), location: nil, category: "Misc",
            lastSyncedAt: Date(), rawJson: "{}", recurringEventId: nil,
            courseId: "course1", eventType: "class"))
        let writer = makeWriter(http: http, db: db)

        try await writer.updateClassification(eventId: "e1", courseId: nil, eventType: nil)

        let body = http.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let priv = (body?["extendedProperties"] as? [String: Any])?["private"] as? [String: Any]
        XCTAssertNotNil(priv)
        XCTAssertTrue(priv?["assistant_course_id"] is NSNull)
        XCTAssertTrue(priv?["assistant_event_type"] is NSNull)
        let cached = try repo.find(id: "e1")
        XCTAssertNil(cached?.courseId)
        XCTAssertNil(cached?.eventType)
    }

    func testClearingTypeResetsColorToCategoryColor() async throws {
        let http = MockHTTPClient()
        http.enqueueJSON("""
        {"id":"e1","summary":"Final",
         "start":{"dateTime":"2026-05-14T10:00:00-04:00"},
         "end":{"dateTime":"2026-05-14T11:00:00-04:00"}}
        """)
        let db = try InMemoryDB.make()
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "e1", calendarId: "cal1", title: "Final",
            startAt: Date(), endAt: Date(), location: nil, category: "Exam",
            lastSyncedAt: Date(), rawJson: "{}", recurringEventId: nil,
            courseId: "course1", eventType: "exam"))
        let writer = makeWriter(http: http, db: db)

        // Clear the event type — color must fall back to the "Exam" category
        // color (not be omitted, which would leave the stale exam-type color).
        try await writer.updateClassification(eventId: "e1", courseId: "course1", eventType: nil)

        let body = http.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let expected = GoogleEventColor.nearestColorId(
            toHex: try CategoryRepository(db: db).resolve("Exam").colorHex)
        XCTAssertEqual(body?["colorId"] as? String, expected)
    }

    func testOfflineOneOffClassEventReplaysWithClassType() async throws {
        let httpOffline = MockHTTPClient()
        let db = try InMemoryDB.make()
        try SettingRepository(db: db).set(AssistantCalendarBootstrap.settingKey, value: "cal1")
        let offlineWriter = CalendarWriter(
            client: GCalClient(http: httpOffline, accessTokenProvider: { "atk" }),
            db: db, isOnline: { false })
        _ = try? await offlineWriter.create(
            title: "Exam", start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600), location: nil, description: nil,
            category: "Misc", recurrence: nil, courseId: "course1", eventType: "exam")
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 1)

        let httpOnline = MockHTTPClient()
        httpOnline.enqueueJSON(GCalFixtures.createdEvent)
        let processor = OutboxProcessor(
            client: GCalClient(http: httpOnline, accessTokenProvider: { "atk" }),
            db: db, quota: QuotaGuard(db: db, cap: 100))
        try await processor.drainOnce()

        let body = httpOnline.sentRequests.last?.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(body?["colorId"] as? String, "11")   // "exam" seeded colorId
        let priv = (body?["extendedProperties"] as? [String: Any])?["private"] as? [String: String]
        XCTAssertEqual(priv?["assistant_course_id"], "course1")
        XCTAssertEqual(priv?["assistant_event_type"], "exam")
    }

    func testGCalEventDecodesExtendedProperties() throws {
        let json = """
        {
          "id": "ev1",
          "summary": "OS Office Hours",
          "colorId": "2",
          "start": { "dateTime": "2026-05-14T10:00:00-04:00" },
          "end":   { "dateTime": "2026-05-14T11:00:00-04:00" },
          "extendedProperties": {
            "private": { "assistant_course_id": "c1", "assistant_event_type": "office_hours" }
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ev = try decoder.decode(GCalEvent.self, from: json)
        XCTAssertEqual(ev.colorId, "2")
        XCTAssertEqual(ev.extendedProperties?.privateProps?["assistant_course_id"], "c1")
        XCTAssertEqual(ev.extendedProperties?.privateProps?["assistant_event_type"], "office_hours")
    }
}
