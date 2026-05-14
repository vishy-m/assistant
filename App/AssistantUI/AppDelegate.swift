import AppKit
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
        menu.addItem(NSMenuItem(title: "Ping daemon",
                                action: #selector(pingDaemon(_:)),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Assistant",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item
    }

    @objc private func pingDaemon(_ sender: Any?) {
        // Wired up in Task 10.
        NSLog("Ping requested (XPC client not wired yet)")
    }
}
