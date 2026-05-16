import SwiftUI

struct SettingsRootView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gear") }
            HotkeysTab().tabItem { Label("Hotkeys", systemImage: "keyboard") }
            APIKeysTab(store: store).tabItem { Label("API Keys", systemImage: "key.fill") }
            GoogleAccountTab(store: store).tabItem { Label("Google", systemImage: "g.circle") }
            BriefingsTab(store: store).tabItem { Label("Briefings", systemImage: "sun.max") }
            StatusTab(store: store).tabItem { Label("Status", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
        .task { await store.reload() }
    }
}
