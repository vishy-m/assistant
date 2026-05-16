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

    /// Set from settings before each auth. In production, prompt the user once
    /// and store in `setting`.
    public static var clientID: String = ""

    /// Google "Desktop app" OAuth clients now also issue a client secret, and
    /// the token endpoint requires it. Set from settings alongside the ID.
    public static var clientSecret: String = ""
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

    /// Held for the lifetime of the flow: the loopback handler owns the local
    /// HTTP listener that catches Google's redirect.
    private var redirectHandler: OIDRedirectHTTPHandler?

    public func authorize(presentingWindow: NSWindow) async throws -> String {
        guard !GCalOAuthConfig.clientID.isEmpty else {
            throw GCalOAuthError.clientIDNotConfigured
        }

        let config = OIDServiceConfiguration(
            authorizationEndpoint: GCalOAuthConfig.authorizationEndpoint,
            tokenEndpoint: GCalOAuthConfig.tokenEndpoint)

        // Desktop loopback flow: a tiny local HTTP server on an ephemeral port
        // catches the `http://127.0.0.1:<port>/` redirect Google sends back.
        // ASWebAuthenticationSession cannot catch an http loopback redirect —
        // that is why the older `byPresenting:presenting:` path stalled.
        let handler = OIDRedirectHTTPHandler(successURL: nil)
        self.redirectHandler = handler
        let redirectURI = handler.startHTTPListener(nil)

        let secret = GCalOAuthConfig.clientSecret.isEmpty ? nil : GCalOAuthConfig.clientSecret
        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: GCalOAuthConfig.clientID,
            clientSecret: secret,
            scopes: GCalOAuthConfig.scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline", "prompt": "consent"])

        let agent = OIDExternalUserAgentMac(presenting: presentingWindow)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            handler.currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                externalUserAgent: agent
            ) { authState, error in
                handler.cancelHTTPListener()
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
