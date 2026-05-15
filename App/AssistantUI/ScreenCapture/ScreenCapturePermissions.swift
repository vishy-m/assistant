import AppKit
import CoreGraphics

enum ScreenCapturePermissions {

    /// Whether the app currently has Screen Recording permission. Cheap call.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the permission prompt (or no-op if already granted).
    /// Returns the granted status synchronously — but macOS only updates this after restart
    /// in some versions; treat the return value as "definitely granted" if true, "maybe not yet" if false.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Open System Settings → Privacy & Security → Screen Recording.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
