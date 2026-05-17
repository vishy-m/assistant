import AppKit
import SwiftUI

/// Hosts the everything dashboard in a standalone window. One shared store so
/// the window keeps loaded data between open/close.
@MainActor
final class DashboardWindow {

    static let shared = DashboardWindow()
    private var window: NSWindow?
    private let store = DashboardStore()
    private var keyObserver: NSObjectProtocol?

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
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [store] _ in
            _Concurrency.Task { @MainActor in
                store.refreshSummary()
                store.refreshEvents()
            }
        }
        store.refreshAll()
    }
}
