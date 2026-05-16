import AppKit

@MainActor
final class GoogleAuthFlow {

    static let shared = GoogleAuthFlow()

    /// Returns true only if the OAuth flow completed and a refresh token was
    /// handed to the daemon. Callers should set their "connected" state from
    /// this result — never assume success.
    @discardableResult
    func connect(presentingWindow: NSWindow) async -> Bool {
        #if canImport(AppAuth)
        do {
            let token = try await GCalOAuth.shared.authorize(presentingWindow: presentingWindow)
            let stored: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                XPCClient.shared.setGoogleRefreshToken(token) { ok in
                    cont.resume(returning: ok)
                }
            }
            let alert = NSAlert()
            if stored {
                alert.messageText = "Connected"
                alert.informativeText = "Google Calendar is now connected."
            } else {
                alert.alertStyle = .warning
                alert.messageText = "Couldn't finish connecting"
                alert.informativeText = "The daemon could not store the Google token."
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return stored
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't connect"
            alert.informativeText = "\(error)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
        #else
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Google Calendar unavailable"
        alert.informativeText = "AppAuth library is not linked into this build."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return false
        #endif
    }
}
