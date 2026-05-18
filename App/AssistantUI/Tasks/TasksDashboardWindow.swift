import AppKit
import SwiftUI

/// Hosts the Tasks dashboard in a standalone window. One shared store so the
/// window keeps its data between open/close.
@MainActor
final class TasksDashboardWindow {

    static let shared = TasksDashboardWindow()
    private var window: NSWindow?
    private let store = TaskStore()

    private init() {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            store.refresh()
            return
        }
        let host = NSHostingController(rootView: TasksDashboardView(store: store))
        let w = NSWindow(contentViewController: host)
        w.setContentSize(NSSize(width: 760, height: 560))
        w.title = "Tasks"
        w.titlebarAppearsTransparent = true
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        store.refresh()
    }
}
