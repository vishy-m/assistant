import Foundation
import GRDB
import AssistantStore

/// Forgets everything tied to the previous Google account when the stored
/// refresh token is replaced or cleared.
///
/// - drops the cached access token (so the old bearer is never served again)
/// - deletes the event cache and the pending-write outbox (queued writes are
///   dropped, not replayed against a different account)
/// - deletes the Assistant calendar id/time zone and the incremental sync tokens
/// - bumps `gcal_account_generation` so a sync that started before the change
///   can tell its results belong to the old account
public enum GCalCredentialReset {

    /// Integer in `setting`. A missing key means generation 0.
    public static let generationKey = "gcal_account_generation"

    static let accountSettingKeys = [
        AssistantCalendarBootstrap.settingKey,
        AssistantCalendarBootstrap.timeZoneKey,
        "gcal_sync_tokens",   // SyncState.key
    ]

    public static func generation(db: AssistantDB) -> Int {
        ((try? SettingRepository(db: db).getCodable(generationKey) as Int?) ?? nil) ?? 0
    }

    public static func accountChanged(db: AssistantDB,
                                      cache: GCalAccessTokenCache = .shared) throws {
        cache.invalidate()
        let next = generation(db: db) + 1
        let generationJSON = try JSONEncoder().encode(next)
        try db.queue.write { db in
            try db.execute(sql: "DELETE FROM gcal_event_cache")
            try db.execute(sql: "DELETE FROM pending_gcal_op")
            for key in accountSettingKeys {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
            }
            try db.execute(sql: """
                INSERT INTO setting (key, value_json, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at
            """, arguments: [generationKey, generationJSON, Date()])
        }
        // A second invalidate covers a refresh that finished while the
        // database was being wiped.
        cache.invalidate()
        NSLog("[GCalAuth] account changed; local Google state reset (generation \(next))")
    }
}
