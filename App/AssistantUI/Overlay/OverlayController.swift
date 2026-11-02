import AppKit
import SwiftUI
import KeyboardShortcuts
import AssistantShared

@MainActor
final class OverlayController {

    static let shared = OverlayController()

    private var panel: OverlayPanel?
    private let state = OverlayState()
    /// True while the panel is hidden for a crop selection. Resign-key events
    /// in that window are not dismissals.
    private var isSuspendingForCrop = false

    private init() {}

    /// Register the global summon hotkey.
    func install() {
        KeyboardShortcuts.onKeyUp(for: .summon) { [weak self] in
            self?.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .crop) { [weak self] in
            guard let self else { return }
            guard let p = self.panel, p.isVisible, p.isKeyWindow else { return }
            self.startCrop()
        }
        KeyboardShortcuts.onKeyUp(for: .summonResume) { [weak self] in
            self?.summonAndResume()
        }
        NotificationCenter.default.addObserver(forName: .overlayPanelDidResignKey,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Hiding the panel for a crop selection is not a dismissal.
                guard self?.isSuspendingForCrop == false else { return }
                // Small delay so the click that caused deactivation finishes first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        guard let self else { return }
                        guard CropDismissGate.shouldDismiss(
                            suspended: self.isSuspendingForCrop,
                            isKey: self.panel?.isKeyWindow ?? false) else { return }
                        self.dismiss()
                    }
                }
            }
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
        // Re-focus the text field on every summon (not just first lifecycle).
        state.focusToken = UUID()
    }

    func summonWithBriefing(_ payload: BriefingPayload) {
        let panel = ensurePanel()
        panel.anchorToBottom()
        state.briefingPayload = payload
        state.mode = .briefing
        panel.updateHeight(220, animated: false)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        state.reset()
        // Crop hotkey is registered locally — KeyboardShortcuts handles scoping via isEnabled.
    }

    private func summonAndResume() {
        let epoch = state.conversationEpoch.current
        XPCClient.shared.getMostRecentSessionId { [weak self] sid in
            guard let self, self.state.conversationEpoch.isCurrent(epoch) else { return }
            if let sid = sid {
                self.state.sessionId = sid
                // Load message history into state.messages
                XPCClient.shared.getMessages(sessionId: sid) { msgs in
                    // Dropped if the overlay was dismissed or a prompt sent meanwhile.
                    guard self.state.conversationEpoch.isCurrent(epoch) else { return }
                    self.state.messages = msgs.map { m in
                        OverlayState.OverlayMessage(
                            role: m.role == "assistant" ? .assistant : .user,
                            text: m.content,
                            modelUsed: m.modelUsed,
                            timestamp: m.createdAt)
                    }
                    self.state.mode = .chat
                    self.summon()
                    self.panel?.updateHeight(420, animated: false)
                }
            } else {
                self.summon()
            }
        }
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
        state.conversationEpoch.bump()
        let epoch = state.conversationEpoch.current

        // Grow panel if entering chat mode for the first time.
        if state.mode == .singleShot { promoteToChatMode() }

        XPCClient.shared.submitPrompt(
            text: text,
            imageData: img?.jpegData,
            imageMediaType: img?.mediaType,
            sessionId: state.sessionId
        ) { [weak self] result in
            // A reply for a dismissed/replaced conversation must not append,
            // write sessionId, or touch isSubmitting (reset already cleared it).
            guard let self, self.state.conversationEpoch.isCurrent(epoch) else { return }
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
                self.state.sessionId = resp.sessionId
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

    private func startCrop() {
        guard ScreenCapturePermissions.isGranted else {
            // First-time: request, then show inline prompt regardless of return value
            ScreenCapturePermissions.request()
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission needed"
            alert.informativeText = "Assistant needs Screen Recording permission to capture from your screen. Open System Settings → Privacy & Security → Screen Recording, enable Assistant, then quit and reopen the app."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                ScreenCapturePermissions.openSystemSettings()
            }
            return
        }

        // Hide the overlay during selection so it doesn't appear in the screenshot.
        // Suspend first: orderOut resigns key, which must not dismiss/reset.
        isSuspendingForCrop = true
        panel?.orderOut(nil)
        Task { @MainActor in
            let rect = await CropSelectionController.shared.selectRegion()
            panel?.orderFront(nil)
            panel?.makeKey()
            isSuspendingForCrop = false
            guard let rect = rect,
                  let (img, jpeg) = ScreenshotCapturer.capture(rect: rect) else {
                return
            }
            state.attachedImage = OverlayState.AttachedImage(
                nsImage: img, jpegData: jpeg, mediaType: "image/jpeg")
        }
    }

    private func promoteToChatMode() {
        state.mode = .chat
        panel?.updateHeight(420, animated: true)
        panel?.anchorToBottom()
    }
}
