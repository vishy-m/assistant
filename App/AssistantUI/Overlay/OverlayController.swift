import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class OverlayController {

    static let shared = OverlayController()

    private var panel: OverlayPanel?
    private let state = OverlayState()

    private init() {}

    /// Register the global summon hotkey.
    func install() {
        KeyboardShortcuts.onKeyUp(for: .summon) { [weak self] in
            self?.toggle()
        }
    }

    func toggle() {
        if let p = panel, p.isVisible {
            dismiss()
        } else {
            summon()
        }
    }

    func summon() {
        let panel = ensurePanel()
        panel.anchorToBottom()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        state.reset()
        // Crop hotkey is registered locally — KeyboardShortcuts handles scoping via isEnabled.
    }

    private func ensurePanel() -> OverlayPanel {
        if let p = panel { return p }
        let p = OverlayPanel()
        let host = NSHostingView(rootView: OverlayRootView(
            state: state,
            onSubmit: { [weak self] in self?.handleSubmit() },
            onDismiss: { [weak self] in self?.dismiss() },
            onClearAttachment: { [weak self] in self?.state.attachedImage = nil }
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        p.contentView = host
        panel = p
        return p
    }

    // Implemented in Task 6
    func handleSubmit() { /* filled in next task */ }
}
