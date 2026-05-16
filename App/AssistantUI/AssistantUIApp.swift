import SwiftUI

@main
struct AssistantUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { SettingsRootView() }
    }
}
