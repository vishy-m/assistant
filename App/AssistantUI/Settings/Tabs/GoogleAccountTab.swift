import SwiftUI
import AppKit
import AssistantShared

struct GoogleAccountTab: View {
    @ObservedObject var store: SettingsStore
    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var isConnecting = false
    @State private var timezoneWarning: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var authStatus: GoogleAuthStatus?

    var body: some View {
        Form {
            Section("OAuth credentials") {
                Text("Create a Desktop App OAuth client at Google Cloud Console → APIs & Services → Credentials. Paste both the client ID and client secret — Google's desktop clients now issue a secret, and the token endpoint requires it. The secret is stored in the Assistant .env file on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Client ID", text: $clientID,
                          prompt: Text("123-abc.apps.googleusercontent.com"))
                SecureField("Client secret", text: $clientSecret,
                            prompt: Text("GOCSPX-…"))
                Button("Save") {
                    _Concurrency.Task { @MainActor in _ = await persistCredentials() }
                }
                .disabled(!GoogleConnectGate.canAttempt(clientID: clientID, secret: clientSecret)
                          || isSaving)
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Link("Open Google Cloud Console →",
                     destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    .font(.caption)
            }
            Section("Connection") {
                if let authStatus, authStatus.needsReconnect {
                    reconnectBanner(authStatus)
                }
                if store.gcalConnected {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    if let warning = timezoneWarning {
                        timezoneBanner(warning)
                    }
                    Button("Disconnect", role: .destructive) {
                        XPCClient.shared.clearGoogleRefreshToken { ok in
                            _Concurrency.Task { @MainActor in
                                if ok {
                                    store.gcalConnected = false
                                    timezoneWarning = nil
                                }
                                refreshAuthStatus()
                            }
                        }
                    }
                    Text("Disconnecting removes this Mac's copy of your Google events and drops calendar changes that haven't synced yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(authStatus?.needsReconnect == true
                           ? "Reconnect Google" : "Connect Google Calendar") {
                        connect()
                    }
                    .disabled(!GoogleConnectGate.canAttempt(clientID: clientID, secret: clientSecret)
                              || isConnecting || isSaving)
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
            refreshAuthStatus()
        }
    }

    /// Saves the client id (settings) and secret (.env). Returns true only
    /// when both writes succeeded; otherwise shows a retryable error and
    /// leaves the fields as typed.
    @MainActor
    private func persistCredentials() async -> Bool {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }
        var s = store.settings
        s.gcalOAuthClientID = id
        store.settings = s
        let settingsSaved = await store.save()
        let secretSaved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            XPCClient.shared.setGoogleClientSecret(secret) { cont.resume(returning: $0) }
        }
        saveError = GoogleConnectGate.saveFailureMessage(settingsSaved: settingsSaved,
                                                         secretSaved: secretSaved)
        return GoogleConnectGate.canStart(settingsSaved: settingsSaved, secretSaved: secretSaved,
                                          clientID: id, secret: secret)
    }

    /// Persists the credentials the daemon will use, then runs OAuth.
    private func connect() {
        isConnecting = true
        _Concurrency.Task { @MainActor in
            defer { isConnecting = false }
            guard await persistCredentials() else { return }
            GCalOAuthConfig.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            GCalOAuthConfig.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            let win = NSApp.keyWindow ?? NSWindow()
            let ok = await GoogleAuthFlow.shared.connect(presentingWindow: win)
            store.gcalConnected = ok
            if ok { refreshTimeZoneWarning() }
            refreshAuthStatus()
        }
    }

    /// Asks the daemon whether its stored Google credentials still work.
    private func refreshAuthStatus() {
        XPCClient.shared.getGoogleAuthStatus { status in
            authStatus = status
            switch status?.state {
            case .connected?, .temporarilyUnavailable?:
                store.gcalConnected = true
                refreshTimeZoneWarning()
            case .notConnected?, .needsReconnect?:
                store.gcalConnected = false
                timezoneWarning = nil
            case .unknown?, nil:
                break
            }
        }
    }

    private func reconnectBanner(_ status: GoogleAuthStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reconnect Google")
                    .font(.callout).fontWeight(.semibold)
                Text(status.reason == "missing_client"
                     ? "The OAuth client ID is missing. Save it above, then reconnect."
                     : "Google rejected the saved sign-in, so calendar sync is paused. Reconnect to resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
