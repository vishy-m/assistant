import SwiftUI
import AppKit

struct OverlayRootView: View {

    @ObservedObject var state: OverlayState
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    let onClearAttachment: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if state.mode == .briefing, let payload = state.briefingPayload {
                BriefingCardView(payload: payload,
                                 onActionable: { _ in /* wired in Task 10 */ },
                                 onDismiss: onDismiss)
                Divider().background(Color.white.opacity(0.1))
            }
            if state.mode == .chat {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(state.messages) { msg in
                            messageRow(msg)
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 400)
                Divider().background(Color.white.opacity(0.1))
            }

            // Input row
            VStack(alignment: .leading, spacing: 8) {
                if let img = state.attachedImage {
                    attachmentChip(img: img)
                }
                HStack(spacing: 10) {
                    Image(systemName: state.isSubmitting ? "ellipsis.circle.fill" : "brain.head.profile")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                    TextField("Ask anything…",
                              text: $state.inputText,
                              axis: .horizontal)
                        .font(.system(size: 17))
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .onSubmit { onSubmit() }
                    if !state.inputText.isEmpty || state.attachedImage != nil {
                        Button(action: onSubmit) {
                            Image(systemName: "arrow.up.circle.fill")
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial)
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear { inputFocused = true }
        .onChange(of: state.focusToken) { _ in inputFocused = true }
        .onExitCommand { onDismiss() }   // SwiftUI's Esc handler
    }

    @ViewBuilder
    private func messageRow(_ msg: OverlayState.OverlayMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(roleLabel(msg.role))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(renderMarkdown(msg.text)).textSelection(.enabled)
                if let model = msg.modelUsed {
                    Text(model).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func roleLabel(_ r: OverlayState.OverlayMessage.Role) -> String {
        switch r { case .user: "you"; case .assistant: "assistant"; case .system: "system" }
    }

    private func renderMarkdown(_ s: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: s, options: options))
            ?? AttributedString(s)
    }

    @ViewBuilder
    private func attachmentChip(img: OverlayState.AttachedImage) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: img.nsImage)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: 36, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("Screen capture attached").font(.system(size: 12))
            Spacer()
            Button(action: onClearAttachment) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
