import AppKit
import Intents
import KeyboardShortcuts
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var focusRelayTimer: Timer?

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
        menu.addItem(NSMenuItem(title: "Classes",
                                action: #selector(openClasses(_:)), keyEquivalent: ""))
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
        startFocusRelay()
        OnboardingWindow.shared.showIfFirstLaunch()
    }

    /// The daemon is a LaunchAgent and can't be granted Focus access, so this
    /// app asks for it and relays the reading every minute.
    private func startFocusRelay() {
        Task { @MainActor in
            let center = INFocusStatusCenter.default
            if center.authorizationStatus == .notDetermined {
                _ = await center.requestAuthorization()
            }
            relayFocusStatus()
            focusRelayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.relayFocusStatus()
            }
        }
    }

    private func relayFocusStatus() {
        let center = INFocusStatusCenter.default
        let authorized = center.authorizationStatus == .authorized
        XPCClient.shared.setFocusStatus(authorized: authorized,
                                        isFocused: authorized ? center.focusStatus.isFocused : nil)
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

    @objc private func openClasses(_ sender: Any?) {
        Task { @MainActor in ClassesDashboardWindow.shared.show() }
    }

    @objc private func openSettings(_ sender: Any?) {
        Task { @MainActor in SettingsWindow.shared.show() }
    }
}
