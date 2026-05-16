import SwiftUI
import AppKit

struct Step3GoogleCalendar: View {
    @ObservedObject var store: SettingsStore
    @State private var clientID = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Connect Google Calendar").font(.title2.bold())
            Text("Assistant writes events to a dedicated 'Assistant' calendar in your Google account. You'll need an OAuth Client ID from Google Cloud Console (Desktop App).")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
            TextField("OAuth Client ID", text: $clientID).frame(maxWidth: 380)
            HStack {
                Link("Get one here →",
                     destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    .font(.caption)
                Spacer()
                Button("Save and connect") {
                    var s = store.settings
                    s.gcalOAuthClientID = clientID
                    store.settings = s
                    _Concurrency.Task {
                        _ = await store.save()
                        GCalOAuthConfig.clientID = clientID
                        let win = NSApp.keyWindow ?? NSWindow()
                        store.gcalConnected = await GoogleAuthFlow.shared.connect(presentingWindow: win)
                    }
                }.disabled(clientID.isEmpty)
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
