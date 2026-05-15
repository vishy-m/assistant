import Foundation

public final class GCalAccessTokenCache: @unchecked Sendable {
    public static let shared = GCalAccessTokenCache()

    private let lock = NSLock()
    private var cachedToken: String?
    private var expiry: Date?

    private let clientID: String
    private let tokenEndpoint: URL
    private let authStore: GCalAuthStore

    public init(clientID: String = "",
                tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
                authStore: GCalAuthStore = GCalAuthStore()) {
        self.clientID = clientID
        self.tokenEndpoint = tokenEndpoint
        self.authStore = authStore
    }

    public func current() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let exp = expiry, exp > Date().addingTimeInterval(30) {
            return cachedToken
        }
        // Synchronous refresh attempt — production code does this async with a refresher.
        cachedToken = (try? refreshSynchronously()) ?? nil
        return cachedToken
    }

    private func refreshSynchronously() throws -> String? {
        guard let rt = try authStore.refreshToken() else { return nil }
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard !clientID.isEmpty else { return nil }
        let form = "client_id=\(clientID)&refresh_token=\(rt)&grant_type=refresh_token"
        req.httpBody = form.data(using: .utf8)
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
}
