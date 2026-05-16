import AppKit
import SwiftUI

@MainActor
final class OnboardingWindow {

    static let shared = OnboardingWindow()
    private var window: NSWindow?
    private let store = SettingsStore()

    private init() {}

    func showIfFirstLaunch() {
        let key = "didCompleteOnboarding"
        if UserDefaults.standard.bool(forKey: key) { return }
        show()
    }

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let view = OnboardingPane(store: store, onFinish: { [weak self] in
            UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
            self?.window?.close()
            self?.window = nil
        })
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.setContentSize(NSSize(width: 540, height: 460))
        w.title = "Welcome to Assistant"
        w.styleMask = [.titled, .closable]
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
