import Foundation
import CryptoKit
import AssistantShared
import AssistantStore
import AssistantLLM

/// Caches a Google access token and refreshes it from the stored refresh token.
/// The OAuth client ID is read from the persisted `app_settings` and the
/// client secret from `.env`, so the daemon picks up credentials the user
/// configures in Settings without a restart.
///
/// A cached token is served only while it is unexpired **and** the
/// credentials it was minted from (refresh token, client id, client secret)
/// are unchanged, so disconnecting or switching accounts takes effect on the
/// next call.
///
/// Failures are classified. When Google rejects the credentials
/// (`invalid_grant`, HTTP 401/403, other 4xx) the cache stops calling the
/// token endpoint until the credentials change, and `authStatus` reports
/// `needsReconnect`. Network and server errors back off exponentially.
public final class GCalAccessTokenCache: @unchecked Sendable {
    public static let shared = GCalAccessTokenCache()

    /// What the token endpoint returned. Only the status code and the OAuth
    /// `error` field are ever inspected; the body is never logged.
    public struct TokenHTTPResult {
        public var data: Data?
        public var statusCode: Int?
        public var error: Error?

        public init(data: Data?, statusCode: Int?, error: Error?) {
            self.data = data
            self.statusCode = statusCode
            self.error = error
        }
    }

    /// Synchronous POST to the token endpoint. Called without the cache lock.
    public typealias Transport = @Sendable (URLRequest) -> TokenHTTPResult

    static let minBackoff: TimeInterval = 60
    static let maxBackoff: TimeInterval = 1800

    private let lock = NSLock()
    private var db: AssistantDB?

    // All of the below are guarded by `lock`.
    private var cachedToken: String?
    private var expiry: Date?
    private var cachedFingerprint: String?
    /// Credentials Google rejected. No network until they change.
    private var rejectedFingerprint: String?
    /// Transient-failure backoff, scoped to the credentials that failed.
    private var retryAfter: Date?
    private var retryFingerprint: String?
    private var backoff: TimeInterval = 0
    private var inFlight: Flight?
    private var status: GoogleAuthStatus = .unknown

    private let tokenEndpoint: URL
    private let authStore: GCalAuthStore
    private let secrets: SecretStore
    private let transport: Transport
    private let now: () -> Date

    public init(tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
                authStore: GCalAuthStore = GCalAuthStore(),
                secrets: SecretStore = SecretStore(),
                transport: @escaping Transport = GCalAccessTokenCache.urlSessionTransport,
                now: @escaping () -> Date = Date.init) {
        self.tokenEndpoint = tokenEndpoint
        self.authStore = authStore
        self.secrets = secrets
        self.transport = transport
        self.now = now
    }

    /// The daemon calls this once at boot so the cache can read the OAuth
    /// client credentials from the `setting` table.
    public func configure(db: AssistantDB) {
        lock.lock(); defer { lock.unlock() }
        self.db = db
    }

    /// Last known authorization state. Non-secret; safe to send to the UI.
    public var authStatus: GoogleAuthStatus {
        lock.lock(); defer { lock.unlock() }
        return status
    }

    /// Drops the cached bearer and any suspension/backoff. Call after the
    /// stored credentials change.
    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        dropToken()
        rejectedFingerprint = nil
        retryAfter = nil
        retryFingerprint = nil
        backoff = 0
    }

    /// Cache hit iff the token is more than 30 s from expiry and was minted
    /// from the same credentials.
    static func allowsCachedToken(expiry: Date?, cachedFingerprint: String?,
                                  fingerprint: String, now: Date) -> Bool {
        guard let expiry, let cachedFingerprint else { return false }
        return expiry > now.addingTimeInterval(30) && cachedFingerprint == fingerprint
    }

    public func current() -> String? {
        let read = readCredentials()

        lock.lock()
        let creds: Credentials
        switch read {
        case .notConnected:
            dropToken()
            setStatus(.init(state: .notConnected))
            lock.unlock()
            return nil
        case .missingClient:
            dropToken()
            setStatus(.init(state: .needsReconnect, reason: "missing_client"))
            lock.unlock()
            return nil
        case .unreadable:
            dropToken()
            setStatus(.init(state: .temporarilyUnavailable, reason: "secrets_unreadable"))
            lock.unlock()
            return nil
        case .ready(let c):
            creds = c
        }

        let fp = creds.fingerprint
        let nowDate = now()
        if Self.allowsCachedToken(expiry: expiry, cachedFingerprint: cachedFingerprint,
                                  fingerprint: fp, now: nowDate) {
            let token = cachedToken
            lock.unlock()
            return token
        }
        if cachedFingerprint != fp { dropToken() }
        if rejectedFingerprint == fp {
            lock.unlock()
            return nil
        }
        if let retryAfter, retryFingerprint == fp, nowDate < retryAfter {
            lock.unlock()
            return nil
        }
        if let flight = inFlight {
            lock.unlock()
            flight.group.wait()
            // Same credentials: share the result. Different credentials: the
            // other flight's result was discarded; evaluate again.
            return flight.fingerprint == fp ? flight.token : current()
        }
        let flight = Flight(fingerprint: fp)
        inFlight = flight
        lock.unlock()

        // Network call without the lock: other callers and configure() are
        // not blocked for up to the 15 s request timeout.
        let outcome = Self.classify(transport(makeRequest(creds)))
        let stillCurrent = readCredentials().fingerprint == fp

        lock.lock()
        inFlight = nil
        if stillCurrent {
            apply(outcome, fingerprint: fp)
            if case .success = outcome { flight.token = cachedToken }
        } else {
            // Credentials changed mid-request: never publish a token minted
            // for the old ones.
            dropToken()
        }
        lock.unlock()
        flight.group.leave()
        return flight.token
    }

    // MARK: - Classification

    enum RefreshOutcome: Equatable {
        case success(token: String, expiresIn: TimeInterval)
        case permanent(reason: String)
        case transient(reason: String)
    }

    static func classify(_ result: TokenHTTPResult) -> RefreshOutcome {
        guard result.error == nil, let code = result.statusCode else {
            return .transient(reason: "transport")
        }
        let root = result.data
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if (200..<300).contains(code) {
            guard let access = root?["access_token"] as? String, !access.isEmpty else {
                return .transient(reason: "malformed")
            }
            let exp = (root?["expires_in"] as? NSNumber)?.doubleValue ?? 3600
            return .success(token: access, expiresIn: exp)
        }
        let reason = sanitizedOAuthError(root?["error"]) ?? "http_\(code)"
        switch code {
        case 408, 429, 500...599:
            return .transient(reason: "http_\(code)")
        case 400..<500:
            return .permanent(reason: reason)
        default:
            return .transient(reason: "http_\(code)")
        }
    }

    /// OAuth error codes are short snake_case ASCII. Anything else is dropped
    /// so a hostile or unexpected body can't leak into logs or the UI.
    static func sanitizedOAuthError(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty, s.count <= 64,
              s.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" })
        else { return nil }
        return s
    }

    // MARK: - Private (lock held)

    private func apply(_ outcome: RefreshOutcome, fingerprint fp: String) {
        switch outcome {
        case let .success(token, expiresIn):
            cachedToken = token
            expiry = now().addingTimeInterval(expiresIn)
            cachedFingerprint = fp
            rejectedFingerprint = nil
            retryAfter = nil
            retryFingerprint = nil
            backoff = 0
            setStatus(.init(state: .connected))
        case let .permanent(reason):
            dropToken()
            rejectedFingerprint = fp
            setStatus(.init(state: .needsReconnect, reason: reason))
        case let .transient(reason):
            dropToken()
            backoff = retryFingerprint == fp
                ? min(max(backoff * 2, Self.minBackoff), Self.maxBackoff)
                : Self.minBackoff
            retryAfter = now().addingTimeInterval(backoff)
            retryFingerprint = fp
            setStatus(.init(state: .temporarilyUnavailable, reason: reason))
        }
    }

    private func dropToken() {
        cachedToken = nil
        expiry = nil
        cachedFingerprint = nil
    }

    private func setStatus(_ new: GoogleAuthStatus) {
        guard new != status else { return }
        status = new
        // Sanitized state + reason code only; logged once per transition.
        NSLog("[GCalAuth] status: \(new.state.rawValue)\(new.reason.map { " (\($0))" } ?? "")")
    }

    // MARK: - Credentials

    private struct Credentials {
        let refreshToken: String
        let clientID: String
        let clientSecret: String

        /// One-way digest; the raw values never leave this struct.
        var fingerprint: String {
            let joined = [refreshToken, clientID, clientSecret].joined(separator: "\u{0}")
            return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private enum CredentialRead {
        case ready(Credentials)
        case notConnected
        case missingClient
        case unreadable

        var fingerprint: String? {
            if case .ready(let c) = self { return c.fingerprint }
            return nil
        }
    }

    private func readCredentials() -> CredentialRead {
        let db: AssistantDB? = { lock.lock(); defer { lock.unlock() }; return self.db }()
        let rt: String?
        do { rt = try authStore.refreshToken() } catch { return .unreadable }
        guard let rt, !rt.isEmpty else { return .notConnected }
        guard let db,
              let settings: AppSettings = try? SettingRepository(db: db).getCodable("app_settings"),
              let id = settings.gcalOAuthClientID, !id.isEmpty else {
            return .missingClient
        }
        let secret: String
        do { secret = try secrets.get(.googleOAuthClientSecret) ?? "" } catch { return .unreadable }
        return .ready(Credentials(refreshToken: rt, clientID: id, clientSecret: secret))
    }

    private func makeRequest(_ creds: Credentials) -> URLRequest {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        // Bounded: this runs synchronously on a caller thread, so a network
        // stall must not block it for the 60s URLRequest default.
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = ["client_id": creds.clientID,
                      "refresh_token": creds.refreshToken,
                      "grant_type": "refresh_token"]
        // A public desktop client may legally have no secret.
        if !creds.clientSecret.isEmpty { fields["client_secret"] = creds.clientSecret }
        req.httpBody = formEncode(fields).data(using: .utf8)
        return req
    }

    private func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }

    // MARK: - Single flight

    private final class Flight: @unchecked Sendable {
        let fingerprint: String
        let group = DispatchGroup()
        /// Written once under the cache lock before `group.leave()`.
        var token: String?

        init(fingerprint: String) {
            self.fingerprint = fingerprint
            group.enter()
        }
    }

    // MARK: - Default transport

    private final class ResultBox: @unchecked Sendable {
        var value = TokenHTTPResult(data: nil, statusCode: nil, error: nil)
    }

    public static let urlSessionTransport: Transport = { req in
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox()
        URLSession.shared.dataTask(with: req) { d, r, e in
            box.value = TokenHTTPResult(data: d, statusCode: (r as? HTTPURLResponse)?.statusCode,
                                        error: e)
            sem.signal()
        }.resume()
        sem.wait()
        return box.value
    }
}
