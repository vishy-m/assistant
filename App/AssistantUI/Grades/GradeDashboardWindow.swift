import AppKit
import SwiftUI

/// Hosts the grade dashboard in a standalone window. One shared store so the
/// window keeps its selection between open/close.
@MainActor
final class GradeDashboardWindow {

    static let shared = GradeDashboardWindow()
    private var window: NSWindow?
    private let store = GradeStore()

    private init() {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            _Concurrency.Task { @MainActor in await store.refreshCourses() }
            return
        }
        let host = NSHostingController(rootView: GradeDashboardView(store: store))
        let w = NSWindow(contentViewController: host)
        w.setContentSize(NSSize(width: 940, height: 620))
        w.title = "Grades"
        w.titlebarAppearsTransparent = true
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        _Concurrency.Task { @MainActor in await store.refreshCourses() }
    }
}
