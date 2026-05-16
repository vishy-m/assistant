import Foundation
import AssistantShared

@MainActor
final class SettingsStore: ObservableObject {

    @Published var settings: AppSettings = .default
    @Published var claudeConfigured: Bool = false
    @Published var openaiConfigured: Bool = false
    @Published var gemmaHostedConfigured: Bool = false
    @Published var gcalConnected: Bool = false

    func reload() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.getSettings { s in
                self.settings = s
                cont.resume()
            }
        }
        await refreshProviderStatuses()
    }

    func refreshProviderStatuses() async {
        let providers = ["claude", "openai", "gemma_hosted"]
        for p in providers {
            let ok: Bool = await withCheckedContinuation { cont in
                XPCClient.shared.getProviderConfigured(provider: p) { cont.resume(returning: $0) }
            }
            switch p {
            case "claude": claudeConfigured = ok
            case "openai": openaiConfigured = ok
            case "gemma_hosted": gemmaHostedConfigured = ok
            default: break
            }
        }
    }

    func setKey(provider: String, key: String) async -> Bool {
        await withCheckedContinuation { cont in
            XPCClient.shared.setProviderAPIKey(provider: provider, key: key) { ok in
                _Concurrency.Task { @MainActor in await self.refreshProviderStatuses() }
                cont.resume(returning: ok)
            }
        }
    }

    func save() async -> Bool {
        await withCheckedContinuation { cont in
            XPCClient.shared.setSettings(settings) { cont.resume(returning: $0) }
        }
    }
}
