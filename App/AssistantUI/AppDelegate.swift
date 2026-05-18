import AppKit
import KeyboardShortcuts
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile",
                                   accessibilityDescription: "Assistant")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open overlay",
                                action: #selector(openOverlay(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Dashboard",
                                action: #selector(openDashboard(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Grades",
                                action: #selector(openGrades(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Tasks",
                                action: #selector(openTasks(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(openSettings(_:)), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Assistant",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        OverlayController.shared.install()
        KeyboardShortcuts.onKeyUp(for: .dashboard) {
            Task { @MainActor in DashboardWindow.shared.show() }
        }
        XPCClient.shared.registerEventClient(BriefingClient.shared.endpoint)
        OnboardingWindow.shared.showIfFirstLaunch()
    }

    @objc private func openOverlay(_ sender: Any?) {
        Task { @MainActor in OverlayController.shared.summon() }
    }

    @objc private func openDashboard(_ sender: Any?) {
        Task { @MainActor in DashboardWindow.shared.show() }
    }

    @objc private func openGrades(_ sender: Any?) {
        Task { @MainActor in GradeDashboardWindow.shared.show() }
    }

    @objc private func openTasks(_ sender: Any?) {
        Task { @MainActor in TasksDashboardWindow.shared.show() }
    }

    @objc private func openSettings(_ sender: Any?) {
        Task { @MainActor in SettingsWindow.shared.show() }
    }
}
