import XCTest
import AssistantShared
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

final class GCalCredentialResetTests: XCTestCase {

    private func seed(_ db: AssistantDB) throws {
        let settings = SettingRepository(db: db)
        try settings.set(AssistantCalendarBootstrap.settingKey, value: "asst_cal")
        try settings.set(AssistantCalendarBootstrap.timeZoneKey, value: "America/Chicago")
        try settings.setCodable("gcal_sync_tokens", value: ["primary": "sync-token"])
        try settings.set("unrelated_key", value: "keep me")
        let repo = GCalRepository(db: db)
        try repo.upsert(GCalEventCache(
            gcalEventId: "ev1", calendarId: "primary", title: "Lecture",
            startAt: Date(), endAt: Date().addingTimeInterval(3600), location: nil,
            category: "class", lastSyncedAt: Date(), rawJson: "{}"))
        try repo.enqueue(PendingGCalOp(
            id: "op1", opType: "insert_event", payloadJson: "{}",
            attempts: 0, lastAttemptAt: nil, createdAt: Date()))
    }

    func testResetWipesAccountScopedStateAndBumpsGeneration() throws {
        let db = try InMemoryDB.make()
        try seed(db)
        XCTAssertEqual(GCalCredentialReset.generation(db: db), 0)

        try GCalCredentialReset.accountChanged(db: db)

        let settings = SettingRepository(db: db)
        XCTAssertNil(try settings.get(AssistantCalendarBootstrap.settingKey))
        XCTAssertNil(try settings.get(AssistantCalendarBootstrap.timeZoneKey))
        XCTAssertNil(try settings.rawData("gcal_sync_tokens"))
        XCTAssertEqual(try settings.get("unrelated_key"), "keep me")
        XCTAssertNil(try GCalRepository(db: db).find(id: "ev1"))
        XCTAssertEqual(try GCalRepository(db: db).pendingOps().count, 0)
        XCTAssertEqual(GCalCredentialReset.generation(db: db), 1)

        try GCalCredentialReset.accountChanged(db: db)
        XCTAssertEqual(GCalCredentialReset.generation(db: db), 2)
    }

    func testResetInvalidatesCachedBearer() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCalCredentialResetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let secrets = SecretStore(fileURL: dir.appendingPathComponent(".env"))
        let auth = GCalAuthStore(secrets: secrets)
        try auth.setRefreshToken("rt-1")
        let db = try InMemoryDB.make()
        var s = AppSettings.default
        s.gcalOAuthClientID = "cid"
        try SettingRepository(db: db).setCodable("app_settings", value: s)

        let body = Data(#"{"access_token":"at-A","expires_in":3600}"#.utf8)
        let cache = GCalAccessTokenCache(
            authStore: auth, secrets: secrets,
            transport: { _ in .init(data: body, statusCode: 200, error: nil) })
        cache.configure(db: db)
        XCTAssertEqual(cache.current(), "at-A")

        try auth.clear()
        try GCalCredentialReset.accountChanged(db: db, cache: cache)
        XCTAssertNil(cache.current())
    }
}
