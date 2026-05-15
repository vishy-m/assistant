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

    func handleSubmit() {
        let text = state.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = state.attachedImage
        guard !text.isEmpty || img != nil else { return }
        guard !state.isSubmitting else { return }

        // Move into chat mode preemptively so the user message is visible immediately.
        if state.mode == .singleShot {
            state.messages.append(.init(role: .user, text: text, modelUsed: nil, timestamp: Date()))
        } else {
            state.messages.append(.init(role: .user, text: text, modelUsed: nil, timestamp: Date()))
        }
        state.inputText = ""
        state.isSubmitting = true

        // Grow panel if entering chat mode for the first time.
        if state.mode == .singleShot { promoteToChatMode() }

        XPCClient.shared.submitPrompt(
            text: text,
            imageData: img?.jpegData,
            imageMediaType: img?.mediaType
        ) { [weak self] result in
            guard let self else { return }
            self.state.isSubmitting = false
            switch result {
            case .success(let resp):
                if let err = resp.errorMessage {
                    self.state.messages.append(.init(role: .system,
                                                     text: "Chain error: \(err)",
                                                     modelUsed: nil,
                                                     timestamp: Date()))
                    return
                }
                self.state.messages.append(.init(role: .assistant,
                                                 text: resp.text.isEmpty ? "(no text — tool actions completed)" : resp.text,
                                                 modelUsed: resp.modelUsed,
                                                 timestamp: Date()))
            case .failure(let err):
                self.state.messages.append(.init(role: .system,
                                                 text: "XPC error: \(err)",
                                                 modelUsed: nil,
                                                 timestamp: Date()))
            }
        }

        // Clear attachment after submit (single-shot semantics).
        state.attachedImage = nil
    }

    private func promoteToChatMode() {
        state.mode = .chat
        panel?.updateHeight(420, animated: true)
        panel?.anchorToBottom()
    }
}
