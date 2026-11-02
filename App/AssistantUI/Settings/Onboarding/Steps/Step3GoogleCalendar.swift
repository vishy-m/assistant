import SwiftUI
import AppKit
import AssistantShared

struct Step3GoogleCalendar: View {
    @ObservedObject var store: SettingsStore
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isWorking = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Connect Google Calendar").font(.title2.bold())
            Text("Assistant writes events to a dedicated 'Assistant' calendar in your Google account. Create a Desktop App OAuth client in Google Cloud Console and paste its client ID and secret. The secret is stored in the Assistant .env file on this Mac.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
            TextField("OAuth Client ID", text: $clientID).frame(maxWidth: 380)
            SecureField("OAuth Client Secret", text: $clientSecret).frame(maxWidth: 380)
            HStack {
                Link("Get one here →",
                     destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    .font(.caption)
                Spacer()
                Button("Save and connect") {
                    let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                    var s = store.settings
                    s.gcalOAuthClientID = id
                    store.settings = s
                    isWorking = true
                    _Concurrency.Task { @MainActor in
                        defer { isWorking = false }
                        let settingsSaved = await store.save()
                        let secretSaved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                            XPCClient.shared.setGoogleClientSecret(secret) { cont.resume(returning: $0) }
                        }
                        saveError = GoogleConnectGate.saveFailureMessage(settingsSaved: settingsSaved,
                                                                         secretSaved: secretSaved)
                        // OAuth only with credentials the daemon can actually read.
                        guard GoogleConnectGate.canStart(settingsSaved: settingsSaved,
                                                         secretSaved: secretSaved,
                                                         clientID: id, secret: secret) else { return }
                        GCalOAuthConfig.clientID = id
                        GCalOAuthConfig.clientSecret = secret
                        let win = NSApp.keyWindow ?? NSWindow()
                        store.gcalConnected = await GoogleAuthFlow.shared.connect(presentingWindow: win)
                    }
                }.disabled(!GoogleConnectGate.canAttempt(clientID: clientID, secret: clientSecret)
                           || isWorking)
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: 380)
            }
            if store.gcalConnected {
                Label("Connected", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
            Text("You can skip this — set it up later in Settings → Google.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(30)
    }
}
