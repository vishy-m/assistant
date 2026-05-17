import AppKit
import SwiftUI

/// Hosts the everything dashboard in a standalone window. One shared store so
/// the window keeps loaded data between open/close.
@MainActor
final class DashboardWindow {

    static let shared = DashboardWindow()
    private var window: NSWindow?
    private let store = DashboardStore()

    private init() {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            store.refreshAll()
            return
        }
        let host = NSHostingController(rootView: DashboardView(store: store))
        let w = NSWindow(contentViewController: host)
        w.setContentSize(NSSize(width: 1180, height: 720))
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.title = "Dashboard"
        w.titlebarAppearsTransparent = true
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        store.refreshAll()
    }
}
