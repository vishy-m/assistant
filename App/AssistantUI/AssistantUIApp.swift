import SwiftUI

@main
struct AssistantUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app: no main window scene. SwiftUI requires a Scene
        // declaration, so we expose an empty Settings scene that's never shown.
        Settings { EmptyView() }
    }
}
