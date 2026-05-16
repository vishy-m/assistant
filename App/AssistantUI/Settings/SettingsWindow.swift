import AppKit
import SwiftUI

/// Hosts the settings UI in a standalone window. A menu-bar (LSUIElement) app
/// can't rely on the SwiftUI `Settings` scene + `showSettingsWindow:` selector,
/// so settings get their own NSWindow — the same pattern as the Grades window.
@MainActor
final class SettingsWindow {

    static let shared = SettingsWindow()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsRootView())
        let w = NSWindow(contentViewController: host)
        w.title = "Assistant Settings"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 560, height: 480))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
