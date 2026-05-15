import Foundation

public enum GCalOAuthConfig {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let scopes = [
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/calendar.events"
    ]

    /// Loopback redirect uses 127.0.0.1 with a dynamic port chosen by AppAuth.
    public static let redirectBaseURL = URL(string: "http://127.0.0.1")!

    /// Replace with your client ID before first auth.
    /// In production, prompt the user once and store in `setting`.
    public static var clientID: String = ""
}

#if canImport(AppAuth)
import AppAuth
import AppKit

public enum GCalOAuthError: Error {
    case clientIDNotConfigured
    case noRefreshToken
    case underlying(Error)
}

@MainActor
public final class GCalOAuth {

    public static let shared = GCalOAuth()

    private var currentSession: OIDExternalUserAgentSession?

    public func authorize(presentingWindow: NSWindow) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let config = OIDServiceConfiguration(
                authorizationEndpoint: GCalOAuthConfig.authorizationEndpoint,
                tokenEndpoint: GCalOAuthConfig.tokenEndpoint)
            guard !GCalOAuthConfig.clientID.isEmpty else {
                cont.resume(throwing: GCalOAuthError.clientIDNotConfigured)
                return
            }
            let redirectURL = URL(string: "\(GCalOAuthConfig.redirectBaseURL.absoluteString):0/oauth/callback")!

            let request = OIDAuthorizationRequest(
                configuration: config,
                clientId: GCalOAuthConfig.clientID,
                clientSecret: nil,
                scopes: GCalOAuthConfig.scopes,
                redirectURL: redirectURL,
                responseType: OIDResponseTypeCode,
                additionalParameters: ["access_type": "offline", "prompt": "consent"])

            self.currentSession = OIDAuthState.authState(byPresenting: request, presenting: presentingWindow) { authState, error in
                if let err = error {
                    cont.resume(throwing: GCalOAuthError.underlying(err))
                    return
                }
                guard let rt = authState?.refreshToken else {
                    cont.resume(throwing: GCalOAuthError.noRefreshToken)
                    return
                }
                cont.resume(returning: rt)
            }
        }
    }
}
#endif
