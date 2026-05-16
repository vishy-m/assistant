import SwiftUI

@main
struct AssistantUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app: settings open via SettingsWindow from the
        // status-bar menu, not this scene. SwiftUI still needs a Scene.
        Settings { EmptyView() }
    }
}
