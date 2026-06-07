import AppKit
import SwiftUI

/// Hosts the Classes dashboard in a standalone window. One shared store so the
/// window keeps its data between open/close.
@MainActor
final class ClassesDashboardWindow {

    static let shared = ClassesDashboardWindow()
    private var window: NSWindow?
    private let store = ClassStore()

    private init() {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            store.refresh()
            return
        }
        let host = NSHostingController(rootView: ClassesDashboardView(store: store))
        let w = NSWindow(contentViewController: host)
        w.setContentSize(NSSize(width: 820, height: 600))
        w.title = "Classes"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        store.refresh()
    }
}
