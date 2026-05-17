import SwiftUI
import AppKit

struct GoogleAccountTab: View {
    @ObservedObject var store: SettingsStore
    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var isConnecting = false
    @State private var timezoneWarning: String?

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
                    if let warning = timezoneWarning {
                        timezoneBanner(warning)
                    }
                    Button("Disconnect", role: .destructive) {
                        XPCClient.shared.clearGoogleRefreshToken { _ in
                            _Concurrency.Task { @MainActor in
                                store.gcalConnected = false
                                timezoneWarning = nil
                            }
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
                            if ok { refreshTimeZoneWarning() }
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
            refreshTimeZoneWarning()
        }
    }

    private func timezoneBanner(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time zone mismatch")
                    .font(.callout).fontWeight(.semibold)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Compares the Google account's display time zone with this Mac's. They
    /// must agree, or events render at a shifted wall-clock time.
    private func refreshTimeZoneWarning() {
        guard store.gcalConnected else { timezoneWarning = nil; return }
        XPCClient.shared.googleAccountTimeZone { accountTZ in
            guard let accountTZ, !accountTZ.isEmpty,
                  let remote = TimeZone(identifier: accountTZ) else {
                timezoneWarning = nil
                return
            }
            let local = TimeZone.current
            let offsetDiff = remote.secondsFromGMT() - local.secondsFromGMT()
            guard offsetDiff != 0 else { timezoneWarning = nil; return }
            let hours = abs(offsetDiff) / 3600
            let unit = hours == 1 ? "hour" : "hours"
            timezoneWarning =
                "Google Calendar shows events in \(accountTZ), but this Mac uses "
                + "\(local.identifier). Events you create may appear shifted by about "
                + "\(hours) \(unit). Fix it in Google Calendar → Settings → Time zone."
        }
    }
}
