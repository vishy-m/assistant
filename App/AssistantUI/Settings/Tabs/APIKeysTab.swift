import SwiftUI

struct APIKeysTab: View {
    @ObservedObject var store: SettingsStore

    @State private var claudeKey = ""
    @State private var openaiKey = ""
    @State private var gemmaKey = ""

    var body: some View {
        Form {
            Section("Claude (Tier 1)") {
                statusRow(configured: store.claudeConfigured)
                SecureField("API key", text: $claudeKey)
                HStack {
                    Button("Save") { _Concurrency.Task { _ = await store.setKey(provider: "claude", key: claudeKey); claudeKey = "" } }
                        .disabled(claudeKey.isEmpty)
                    Button("Clear") { _Concurrency.Task { _ = await store.setKey(provider: "claude", key: "") } }
                }
                Link("Get one at console.anthropic.com →",
                     destination: URL(string: "https://console.anthropic.com/")!)
                    .font(.caption)
            }
            Section("OpenAI (Tier 2)") {
                statusRow(configured: store.openaiConfigured)
                SecureField("API key", text: $openaiKey)
                HStack {
                    Button("Save") { _Concurrency.Task { _ = await store.setKey(provider: "openai", key: openaiKey); openaiKey = "" } }
                        .disabled(openaiKey.isEmpty)
                    Button("Clear") { _Concurrency.Task { _ = await store.setKey(provider: "openai", key: "") } }
                }
                Link("Get one at platform.openai.com →",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
            Section("Gemma 4 hosted (Tier 3)") {
                statusRow(configured: store.gemmaHostedConfigured)
                SecureField("API key", text: $gemmaKey)
                HStack {
                    Button("Save") { _Concurrency.Task { _ = await store.setKey(provider: "gemma_hosted", key: gemmaKey); gemmaKey = "" } }
                        .disabled(gemmaKey.isEmpty)
                    Button("Clear") { _Concurrency.Task { _ = await store.setKey(provider: "gemma_hosted", key: "") } }
                }
                Text("Default endpoint is Google AI Studio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local Gemma 4 (Tier 4)") {
                Text("No key required. Install via brew install ollama && ollama pull gemma4.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .task { await store.refreshProviderStatuses() }
    }

    @ViewBuilder
    private func statusRow(configured: Bool) -> some View {
        HStack {
            Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(configured ? .green : .orange)
            Text(configured ? "Configured" : "Not configured")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
