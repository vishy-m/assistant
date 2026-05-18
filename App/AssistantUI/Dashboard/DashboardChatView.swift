import SwiftUI

struct DashboardChatView: View {
    @ObservedObject var store: DashboardStore
    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 0) {
            EyebrowLabel("Assistant")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.messages) { msg in
                            messageBubble(msg)
                        }
                        if store.isSending {
                            Text("Thinking…")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 14)
                }
                .onChange(of: store.messages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Ask the assistant…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(GradeTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(store.isSending)
            }
            .padding(12)
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        if text.lowercased() == "/clear" {
            store.clearChat()
            return
        }
        store.send(text)
    }

    @ViewBuilder
    private func messageBubble(_ msg: DashboardStore.ChatMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer(minLength: 24) }
            Text(rendered(msg.text))
                .font(.callout)
                .padding(8)
                .background(isUser ? GradeTheme.accent.opacity(0.15) : GradeTheme.panelBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(msg.role == .system ? Color.red : Color.primary)
            if !isUser { Spacer(minLength: 24) }
        }
        .id(msg.id)
    }

    private func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
