import XCTest
import AssistantShared
@testable import AssistantGCal
@testable import AssistantStore
@testable import AssistantLLM

/// Scripted token endpoint. Never touches the network.
private final class FakeTokenEndpoint: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [GCalAccessTokenCache.TokenHTTPResult] = []
    private(set) var requestCount = 0
    var onRequest: (() -> Void)?

    func enqueue(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        responses.append(.init(data: Data(body.utf8), statusCode: status, error: nil))
    }

    func enqueueTransportError() {
        lock.lock(); defer { lock.unlock() }
        responses.append(.init(data: nil, statusCode: nil, error: URLError(.notConnectedToInternet)))
    }

    func handle(_ req: URLRequest) -> GCalAccessTokenCache.TokenHTTPResult {
        onRequest?()
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        guard !responses.isEmpty else {
            return .init(data: nil, statusCode: nil, error: URLError(.cannotConnectToHost))
        }
        return responses.removeFirst()
    }
}

final class GCalAccessTokenCacheTests: XCTestCase {

    private var dir: URL!
    private var secrets: SecretStore!
    private var authStore: GCalAuthStore!
    private var db: AssistantDB!
    private var endpoint: FakeTokenEndpoint!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCalAccessTokenCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        secrets = SecretStore(fileURL: dir.appendingPathComponent(".env"))
        authStore = GCalAuthStore(secrets: secrets)
        db = try InMemoryDB.make()
        var s = AppSettings.default
        s.gcalOAuthClientID = "client-id"
        try SettingRepository(db: db).setCodable("app_settings", value: s)
        try secrets.set(.googleOAuthClientSecret, value: "client-secret")
        try authStore.setRefreshToken("rt-1")
        endpoint = FakeTokenEndpoint()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeCache() -> GCalAccessTokenCache {
        let endpoint = self.endpoint!
        let cache = GCalAccessTokenCache(
            authStore: authStore,
            secrets: secrets,
            transport: { endpoint.handle($0) },
            now: { [unowned self] in self.clock })
        cache.configure(db: db)
        return cache
    }

    private func ok(_ token: String, expiresIn: Int = 3600) -> String {
        #"{"access_token":"\#(token)","expires_in":\#(expiresIn),"token_type":"Bearer"}"#
    }

    // MARK: - Pure cache-hit rule

    func testAllowsCachedTokenRequiresFutureExpiryAndMatchingFingerprint() {
        let now = Date()
        XCTAssertTrue(GCalAccessTokenCache.allowsCachedToken(
            expiry: now.addingTimeInterval(600), cachedFingerprint: "a", fingerprint: "a", now: now))
        XCTAssertFalse(GCalAccessTokenCache.allowsCachedToken(
            expiry: now.addingTimeInterval(600), cachedFingerprint: "a", fingerprint: "b", now: now))
        XCTAssertFalse(GCalAccessTokenCache.allowsCachedToken(
            expiry: now.addingTimeInterval(600), cachedFingerprint: nil, fingerprint: "a", now: now))
        XCTAssertFalse(GCalAccessTokenCache.allowsCachedToken(
            expiry: now.addingTimeInterval(20), cachedFingerprint: "a", fingerprint: "a", now: now))
        XCTAssertFalse(GCalAccessTokenCache.allowsCachedToken(
            expiry: nil, cachedFingerprint: "a", fingerprint: "a", now: now))
    }

    // MARK: - Success + caching

    func testSuccessIsCachedUntilExpiry() {
        endpoint.enqueue(status: 200, body: ok("at-A"))
        let cache = makeCache()
        XCTAssertEqual(cache.current(), "at-A")
        XCTAssertEqual(cache.current(), "at-A")
        XCTAssertEqual(endpoint.requestCount, 1)
        XCTAssertEqual(cache.authStatus.state, .connected)
    }

    // MARK: - A1 #6 / A2-02: credential change drops the old bearer

    func testReplacingRefreshTokenDropsCachedBearer() throws {
        endpoint.enqueue(status: 200, body: ok("at-A"))
        let cache = makeCache()
        XCTAssertEqual(cache.current(), "at-A")
        try authStore.setRefreshToken("rt-2")
        endpoint.enqueue(status: 200, body: ok("at-B"))
        XCTAssertEqual(cache.current(), "at-B")
        XCTAssertEqual(endpoint.requestCount, 2)
    }

    func testClearingRefreshTokenDropsCachedBearerWithoutNetwork() throws {
        endpoint.enqueue(status: 200, body: ok("at-A"))
        let cache = makeCache()
        XCTAssertEqual(cache.current(), "at-A")
        try authStore.clear()
        XCTAssertNil(cache.current())
        XCTAssertEqual(endpoint.requestCount, 1)
        XCTAssertEqual(cache.authStatus.state, .notConnected)
    }

    func testChangingClientSecretDropsCachedBearer() throws {
        endpoint.enqueue(status: 200, body: ok("at-A"))
        let cache = makeCache()
        XCTAssertEqual(cache.current(), "at-A")
        try secrets.set(.googleOAuthClientSecret, value: "other-secret")
        endpoint.enqueue(status: 200, body: ok("at-B"))
        XCTAssertEqual(cache.current(), "at-B")
    }

    func testInvalidateDropsCachedBearer() {
        endpoint.enqueue(status: 200, body: ok("at-A"))
        endpoint.enqueue(status: 200, body: ok("at-B"))
        let cache = makeCache()
        XCTAssertEqual(cache.current(), "at-A")
        cache.invalidate()
        XCTAssertEqual(cache.current(), "at-B")
    }

    func testCredentialChangeDuringRefreshDiscardsResult() throws {
        endpoint.enqueue(status: 200, body: ok("at-A"))
        let store = authStore!
        endpoint.onRequest = { try? store.setRefreshToken("rt-changed") }
        let cache = makeCache()
        XCTAssertNil(cache.current(), "a token minted for the old credentials must not be served")
        endpoint.onRequest = nil
        endpoint.enqueue(status: 200, body: ok("at-B"))
        XCTAssertEqual(cache.current(), "at-B")
    }

    // MARK: - A2-01: permanent failures stop retrying

    func testInvalidGrantSuspendsUntilRefreshTokenChanges() throws {
        endpoint.enqueue(status: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)
        let cache = makeCache()
        XCTAssertNil(cache.current())
        XCTAssertNil(cache.current())
        XCTAssertNil(cache.current())
        XCTAssertEqual(endpoint.requestCount, 1, "a rejected refresh token must not be retried")
        XCTAssertEqual(cache.authStatus.state, .needsReconnect)
        XCTAssertEqual(cache.authStatus.reason, "invalid_grant")
        XCTAssertTrue(cache.authStatus.needsReconnect)

        try authStore.setRefreshToken("rt-new")
        endpoint.enqueue(status: 200, body: ok("at-new"))
        XCTAssertEqual(cache.current(), "at-new")
        XCTAssertEqual(endpoint.requestCount, 2)
        XCTAssertEqual(cache.authStatus.state, .connected)
    }

    func testHTTP401And403ArePermanent() throws {
        for status in [401, 403] {
            endpoint = FakeTokenEndpoint()
            endpoint.enqueue(status: status, body: #"{"error":"unauthorized_client"}"#)
            let cache = makeCache()
            XCTAssertNil(cache.current())
            XCTAssertNil(cache.current())
            XCTAssertEqual(endpoint.requestCount, 1, "HTTP \(status)")
            XCTAssertEqual(cache.authStatus.state, .needsReconnect)
        }
    }

    func testTransientFailureBacksOff() {
        endpoint.enqueue(status: 503, body: "upstream")
        let cache = makeCache()
        XCTAssertNil(cache.current())
        XCTAssertNil(cache.current())
        XCTAssertEqual(endpoint.requestCount, 1, "no retry inside the backoff window")
        XCTAssertEqual(cache.authStatus.state, .temporarilyUnavailable)
        XCTAssertFalse(cache.authStatus.needsReconnect)

        clock = clock.addingTimeInterval(3600)
        endpoint.enqueue(status: 200, body: ok("at-A"))
        XCTAssertEqual(cache.current(), "at-A")
        XCTAssertEqual(endpoint.requestCount, 2)
    }

    func testTransportErrorIsTransient() {
        endpoint.enqueueTransportError()
        let cache = makeCache()
        XCTAssertNil(cache.current())
        XCTAssertEqual(cache.authStatus.state, .temporarilyUnavailable)
        XCTAssertEqual(cache.authStatus.reason, "transport")
    }

    func testMissingRefreshTokenIsNotConnectedAndSkipsNetwork() throws {
        try authStore.clear()
        let cache = makeCache()
        XCTAssertNil(cache.current())
        XCTAssertEqual(endpoint.requestCount, 0)
        XCTAssertEqual(cache.authStatus.state, .notConnected)
    }

    func testMissingClientIDSkipsNetwork() throws {
        try SettingRepository(db: db).setCodable("app_settings", value: AppSettings.default)
        let cache = makeCache()
        XCTAssertNil(cache.current())
        XCTAssertEqual(endpoint.requestCount, 0)
        XCTAssertEqual(cache.authStatus.state, .needsReconnect)
        XCTAssertEqual(cache.authStatus.reason, "missing_client")
    }

    func testStatusNeverContainsSecrets() throws {
        endpoint.enqueue(status: 400, body: #"{"error":"rt-1 client-secret <script>"}"#)
        let cache = makeCache()
        _ = cache.current()
        let status = cache.authStatus
        let encoded = String(data: try JSONEncoder().encode(status), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("rt-1"))
        XCTAssertFalse(encoded.contains("client-secret"))
        XCTAssertFalse(encoded.contains("<"))
        XCTAssertEqual(status.state, .needsReconnect)
    }

    // MARK: - NEW-01: single-flight, lock not held across the request

    func testConcurrentCallersShareOneRefresh() {
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        endpoint.enqueue(status: 200, body: ok("at-A"))
        endpoint.onRequest = { entered.signal(); gate.wait() }
        let cache = makeCache()

        let group = DispatchGroup()
        var results = [String?](repeating: nil, count: 2)
        let resultsLock = NSLock()
        for i in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                let t = cache.current()
                resultsLock.lock(); results[i] = t; resultsLock.unlock()
                group.leave()
            }
            if i == 0 { entered.wait() }
        }
        // configure() must not block behind the in-flight request.
        let configured = expectation(description: "configure returns while refresh is in flight")
        DispatchQueue.global().async { cache.configure(db: self.db); configured.fulfill() }
        wait(for: [configured], timeout: 2)
        // Give the second caller time to join the flight.
        Thread.sleep(forTimeInterval: 0.2)
        gate.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(endpoint.requestCount, 1)
        XCTAssertEqual(results, ["at-A", "at-A"])
    }
}
