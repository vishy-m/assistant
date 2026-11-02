import Foundation
import GRDB
import AssistantStore
import AssistantLLM

/// Migration for installs created before the OAuth client secret moved out of
/// the SQLite `app_settings` blob into the secrets `.env` file.
///
/// Copies a legacy `gcalOAuthClientSecret` into `.env` (verifying the write),
/// then removes only that key from the raw `app_settings` JSON, leaving every
/// other key as it was. It never decodes `AppSettings`, so an old settings
/// shape the current model can't decode is still cleaned. Any failure leaves
/// the SQLite key in place and the next launch retries.
public enum OAuthSecretMigration {

    static let legacyKey = "gcalOAuthClientSecret"
    static let settingsKey = "app_settings"

    public static func run(db: AssistantDB, secrets: SecretStore = SecretStore()) {
        let settings = SettingRepository(db: db)
        guard let raw = (try? settings.rawData(settingsKey)) ?? nil,
              let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let legacyValue = obj[legacyKey] else {
            return
        }

        do {
            if let legacy = legacyValue as? String, !legacy.isEmpty {
                let existing = try secrets.get(.googleOAuthClientSecret)
                switch existing {
                case nil:
                    try secrets.set(.googleOAuthClientSecret, value: legacy)
                    guard try secrets.get(.googleOAuthClientSecret) == legacy else {
                        NSLog("[OAuthSecretMigration] failed: .env read-back mismatch; legacy copy kept")
                        return
                    }
                case legacy?:
                    break
                default:
                    // Two different secrets: keep both copies for a human to resolve.
                    NSLog("[OAuthSecretMigration] .env already holds a different client secret; legacy copy kept")
                    return
                }
            }
            // Non-string or empty legacy values carry nothing worth copying.

            var cleaned = obj
            cleaned.removeValue(forKey: legacyKey)
            let data = try JSONSerialization.data(withJSONObject: cleaned)
            try db.queue.write { db in
                try db.execute(sql: """
                    INSERT INTO setting (key, value_json, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        value_json = excluded.value_json,
                        updated_at = excluded.updated_at
                """, arguments: [settingsKey, data, Date()])
            }

            guard let after = try settings.rawData(settingsKey),
                  let afterObj = try JSONSerialization.jsonObject(with: after) as? [String: Any],
                  afterObj[legacyKey] == nil else {
                NSLog("[OAuthSecretMigration] failed: legacy key still present after rewrite")
                return
            }
            NSLog("[OAuthSecretMigration] moved Google client secret to .env and removed the SQLite copy")
        } catch {
            NSLog("[OAuthSecretMigration] failed: \(error)")
        }
    }
}
