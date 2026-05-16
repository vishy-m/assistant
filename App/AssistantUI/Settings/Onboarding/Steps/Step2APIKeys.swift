import SwiftUI

struct Step2APIKeys: View {
    @ObservedObject var store: SettingsStore
    @State private var claudeKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect Claude").font(.title2.bold())
            Text("Assistant uses Claude as its primary brain. Paste an API key from console.anthropic.com — it's stored securely in your macOS Keychain and only sent to Anthropic.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 40)
            SecureField("Claude API key", text: $claudeKey).frame(maxWidth: 320)
            Button("Save key") {
                _Concurrency.Task { _ = await store.setKey(provider: "claude", key: claudeKey); claudeKey = "" }
            }.disabled(claudeKey.isEmpty)
            if store.claudeConfigured {
                Label("Saved", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
            Text("Optional: configure OpenAI / hosted Gemma as fallbacks in Settings later.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(30)
    }
}
