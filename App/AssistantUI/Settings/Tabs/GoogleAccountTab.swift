import SwiftUI
import AppKit

struct GoogleAccountTab: View {
    @ObservedObject var store: SettingsStore
    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section("OAuth credentials") {
                Text("Create a Desktop App OAuth client at Google Cloud Console → APIs & Services → Credentials. Paste both the client ID and client secret — Google's desktop clients now issue a secret, and the token endpoint requires it. The secret is stored in your macOS Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Client ID", text: $clientID,
                          prompt: Text("123-abc.apps.googleusercontent.com"))
                SecureField("Client secret", text: $clientSecret,
                            prompt: Text("GOCSPX-…"))
                Button("Save") {
                    var s = store.settings
                    s.gcalOAuthClientID = clientID
                    store.settings = s
                    let secret = clientSecret
                    _Concurrency.Task {
                        _ = await store.save()
                        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                            XPCClient.shared.setGoogleClientSecret(secret) { _ in cont.resume() }
                        }
                    }
                }
                .disabled(clientID.isEmpty)
                Link("Open Google Cloud Console →",
                     destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    .font(.caption)
            }
            Section("Connection") {
                if store.gcalConnected {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Disconnect", role: .destructive) {
                        XPCClient.shared.clearGoogleRefreshToken { _ in
                            _Concurrency.Task { @MainActor in store.gcalConnected = false }
                        }
                    }
                } else {
                    Button("Connect Google Calendar") {
                        guard let cid = store.settings.gcalOAuthClientID, !cid.isEmpty else { return }
                        GCalOAuthConfig.clientID = cid
                        GCalOAuthConfig.clientSecret = clientSecret
                        isConnecting = true
                        _Concurrency.Task { @MainActor in
                            let win = NSApp.keyWindow ?? NSWindow()
                            let ok = await GoogleAuthFlow.shared.connect(presentingWindow: win)
                            isConnecting = false
                            store.gcalConnected = ok
                        }
                    }
                    .disabled((store.settings.gcalOAuthClientID?.isEmpty ?? true) || isConnecting)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            clientID = store.settings.gcalOAuthClientID ?? ""
            XPCClient.shared.getGoogleClientSecret { secret in
                clientSecret = secret ?? ""
            }
        }
    }
}
