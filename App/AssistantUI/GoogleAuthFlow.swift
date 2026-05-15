import AppKit

@MainActor
final class GoogleAuthFlow {

    static let shared = GoogleAuthFlow()

    func connect(presentingWindow: NSWindow) async {
        #if canImport(AppAuth)
        do {
            let token = try await GCalOAuth.shared.authorize(presentingWindow: presentingWindow)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                XPCClient.shared.setGoogleRefreshToken(token) { _ in
                    cont.resume()
                }
            }
            let alert = NSAlert()
            alert.messageText = "Connected"
            alert.informativeText = "Google Calendar is now connected."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't connect"
            alert.informativeText = "\(error)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        #else
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Google Calendar unavailable"
        alert.informativeText = "AppAuth library is not linked into this build. Wire it up via Task 12 of sub-plan #4 (xcodegen + project.yml)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        #endif
    }
}
