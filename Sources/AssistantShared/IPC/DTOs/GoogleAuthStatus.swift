import Foundation

/// Non-secret summary of the daemon's Google authorization, sent to the UI.
/// `reason` is a sanitized code (an OAuth `error` value such as
/// `invalid_grant`, or `http_<status>`, `transport`, `malformed`,
/// `missing_client`) and never contains a token, secret, or response body.
public struct GoogleAuthStatus: Codable, Equatable, Sendable {

    public enum State: String, Codable, Sendable {
        /// No token request has run yet.
        case unknown
        /// The last token refresh succeeded.
        case connected
        /// No refresh token is stored.
        case notConnected
        /// Google rejected the credentials, or they are incomplete. Retrying
        /// will not help until the user reconnects or edits them.
        case needsReconnect
        /// Network or server trouble. The daemon retries with backoff.
        case temporarilyUnavailable
    }

    public var state: State
    public var reason: String?

    public init(state: State, reason: String? = nil) {
        self.state = state
        self.reason = reason
    }

    public var needsReconnect: Bool { state == .needsReconnect }

    public static let unknown = GoogleAuthStatus(state: .unknown)
}
