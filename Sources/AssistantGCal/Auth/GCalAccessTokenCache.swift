import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM

/// Caches a Google access token and refreshes it from the stored refresh token.
/// The OAuth client ID + secret are read from the persisted `app_settings`, so
/// the daemon picks them up after the user configures Google in Settings —
/// no restart required.
public final class GCalAccessTokenCache: @unchecked Sendable {
    public static let shared = GCalAccessTokenCache()

    private let lock = NSLock()
    private var cachedToken: String?
    private var expiry: Date?
    private var db: AssistantDB?

    private let tokenEndpoint: URL
    private let authStore: GCalAuthStore

    public init(tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
                authStore: GCalAuthStore = GCalAuthStore()) {
        self.tokenEndpoint = tokenEndpoint
        self.authStore = authStore
    }

    /// The daemon calls this once at boot so the cache can read the OAuth
    /// client credentials from the `setting` table.
    public func configure(db: AssistantDB) {
        lock.lock(); defer { lock.unlock() }
        self.db = db
    }

    public func current() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let exp = expiry, exp > Date().addingTimeInterval(30) {
            return cachedToken
        }
        cachedToken = (try? refreshSynchronously()) ?? nil
        return cachedToken
    }

    /// Reads the OAuth client ID from settings and the client secret from Keychain.
    private func clientCredentials() -> (id: String, secret: String)? {
        guard let db else { return nil }
        guard let settings: AppSettings = try? SettingRepository(db: db).getCodable("app_settings"),
              let id = settings.gcalOAuthClientID, !id.isEmpty else {
            return nil
        }
        let secret = ((try? KeychainStore().get(.googleOAuthClientSecret)) ?? nil) ?? ""
        return (id, secret)
    }

    private func refreshSynchronously() throws -> String? {
        guard let rt = try authStore.refreshToken() else { return nil }
        guard let creds = clientCredentials() else { return nil }

        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        // Bounded: this runs synchronously on a caller thread, so a network
        // stall must not block it for the 60s URLRequest default.
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = ["client_id": creds.id,
                      "refresh_token": rt,
                      "grant_type": "refresh_token"]
        if !creds.secret.isEmpty { fields["client_secret"] = creds.secret }
        req.httpBody = formEncode(fields).data(using: .utf8)

        let sem = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        URLSession.shared.dataTask(with: req) { d, r, e in
            result = (d, r, e)
            sem.signal()
        }.resume()
        sem.wait()
        guard let data = result.0,
              let rootAny = try? JSONSerialization.jsonObject(with: data),
              let root = rootAny as? [String: Any],
              let access = root["access_token"] as? String else {
            return nil
        }
        let expSec = root["expires_in"] as? Double ?? 3600
        expiry = Date().addingTimeInterval(expSec)
        return access
    }

    private func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }
}
