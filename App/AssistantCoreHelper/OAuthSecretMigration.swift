import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM

/// One-time migration for installs created before the OAuth client secret was
/// moved out of the SQLite `app_settings` blob into the secrets `.env` file.
///
/// The earlier security fix dropped `gcalOAuthClientSecret` from `AppSettings`
/// but never relocated the persisted value — the plaintext secret was left
/// orphaned in SQLite where the daemon could no longer read it, so token
/// refresh silently failed with 401s on every Calendar call. This moves the
/// secret into `.env` and rewrites `app_settings` so no plaintext copy
/// remains on disk.
enum OAuthSecretMigration {

    static func run(db: AssistantDB) {
        let secrets = SecretStore()

        // Already in .env — nothing to migrate.
        if let existing = (try? secrets.get(.googleOAuthClientSecret)) ?? nil,
           !existing.isEmpty {
            return
        }

        let settings = SettingRepository(db: db)
        guard let raw = (try? settings.rawData("app_settings")) ?? nil,
              let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let secret = obj["gcalOAuthClientSecret"] as? String,
              !secret.isEmpty else {
            return
        }

        do {
            try secrets.set(.googleOAuthClientSecret, value: secret)
            // Re-decode + re-encode through AppSettings, which no longer has
            // the secret field — this strips the plaintext copy from SQLite.
            if let decoded: AppSettings = try? settings.getCodable("app_settings") {
                try settings.setCodable("app_settings", value: decoded)
            }
            NSLog("[OAuthSecretMigration] moved Google client secret to .env")
        } catch {
            NSLog("[OAuthSecretMigration] failed: \(error)")
        }
    }
}
