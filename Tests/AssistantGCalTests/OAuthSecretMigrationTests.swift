import XCTest
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

final class OAuthSecretMigrationTests: XCTestCase {

    private var dir: URL!
    private var secrets: SecretStore!
    private var db: AssistantDB!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OAuthSecretMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        secrets = SecretStore(fileURL: dir.appendingPathComponent(".env"))
        db = try InMemoryDB.make()
    }

    override func tearDownWithError() throws {
        if let dir {
            chmod(dir.path, 0o700)
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func writeRaw(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try db.queue.write { db in
            try db.execute(sql: """
                INSERT INTO setting (key, value_json, updated_at) VALUES ('app_settings', ?, ?)
                ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json
                """, arguments: [data, Date()])
        }
    }

    private func readRaw() throws -> [String: Any] {
        let data = try XCTUnwrap(try SettingRepository(db: db).rawData("app_settings"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDestinationAlreadySetStillStripsLegacyKey() throws {
        try secrets.set(.googleOAuthClientSecret, value: "S")
        try writeRaw(["gcalOAuthClientSecret": "S", "morningBriefingHour": 7,
                      "nested": ["a": 1]])

        OAuthSecretMigration.run(db: db, secrets: secrets)

        let raw = try readRaw()
        XCTAssertNil(raw["gcalOAuthClientSecret"])
        XCTAssertEqual(raw["morningBriefingHour"] as? Int, 7)
        XCTAssertEqual((raw["nested"] as? [String: Int])?["a"], 1)
        XCTAssertEqual(try secrets.get(.googleOAuthClientSecret), "S")
    }

    func testUndecodableOldSettingsStillMigrates() throws {
        // No preferredOllamaModel etc: JSONDecoder can't build AppSettings.
        try writeRaw(["gcalOAuthClientSecret": "LEGACY", "gcalOAuthClientID": "cid",
                      "morningBriefingHour": 8])

        OAuthSecretMigration.run(db: db, secrets: secrets)

        XCTAssertEqual(try secrets.get(.googleOAuthClientSecret), "LEGACY")
        let raw = try readRaw()
        XCTAssertNil(raw["gcalOAuthClientSecret"])
        XCTAssertEqual(raw["gcalOAuthClientID"] as? String, "cid")
        XCTAssertEqual(raw["morningBriefingHour"] as? Int, 8)
    }

    func testDifferingDestinationDoesNotStrip() throws {
        try secrets.set(.googleOAuthClientSecret, value: "NEW")
        try writeRaw(["gcalOAuthClientSecret": "OLD"])

        OAuthSecretMigration.run(db: db, secrets: secrets)

        XCTAssertEqual(try readRaw()["gcalOAuthClientSecret"] as? String, "OLD")
        XCTAssertEqual(try secrets.get(.googleOAuthClientSecret), "NEW")
    }

    func testCopyFailureLeavesKeyForRetry() throws {
        try writeRaw(["gcalOAuthClientSecret": "LEGACY"])
        // Read-only directory: the atomic temp-file write fails.
        chmod(dir.path, 0o500)

        OAuthSecretMigration.run(db: db, secrets: secrets)

        chmod(dir.path, 0o700)
        XCTAssertEqual(try readRaw()["gcalOAuthClientSecret"] as? String, "LEGACY")
        XCTAssertNil(try secrets.get(.googleOAuthClientSecret))
    }

    func testNonStringKeyIsRemovedWithoutCopy() throws {
        try writeRaw(["gcalOAuthClientSecret": 42, "keep": true])

        OAuthSecretMigration.run(db: db, secrets: secrets)

        let raw = try readRaw()
        XCTAssertNil(raw["gcalOAuthClientSecret"])
        XCTAssertEqual(raw["keep"] as? Bool, true)
        XCTAssertNil(try secrets.get(.googleOAuthClientSecret))
    }

    func testNoLegacyKeyLeavesSettingsUntouched() throws {
        try writeRaw(["morningBriefingHour": 9])
        let before = try SettingRepository(db: db).rawData("app_settings")
        OAuthSecretMigration.run(db: db, secrets: secrets)
        XCTAssertEqual(try SettingRepository(db: db).rawData("app_settings"), before)
    }
}
