import SwiftUI

struct StatusTab: View {
    @ObservedObject var store: SettingsStore
    @State private var pingResult: String = "?"

    var body: some View {
        Form {
            Section("Daemon") {
                HStack {
                    Text("Ping")
                    Spacer()
                    Text(pingResult).font(.system(.body, design: .monospaced))
                }
                Button("Re-ping") {
                    XPCClient.shared.ping { result in
                        pingResult = (try? result.get()) ?? "fail"
                    }
                }
            }
            Section("LLM providers") {
                row("Claude (Tier 1)", store.claudeConfigured)
                row("OpenAI (Tier 2)", store.openaiConfigured)
                row("Gemini (Tier 3)", store.geminiConfigured)
                row("Gemma hosted (Tier 4)", store.gemmaHostedConfigured)
                row("Gemma local (Tier 5)", true)
            }
            Section("Google Calendar") {
                row("Connected", store.gcalConnected)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            XPCClient.shared.ping { r in pingResult = (try? r.get()) ?? "fail" }
        }
    }

    private func row(_ label: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
            Text(label)
        }
    }
}
