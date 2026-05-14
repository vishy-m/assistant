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
        menu.addItem(NSMenuItem(title: "Show today",
                                action: #selector(showToday(_:)),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Assistant",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item
    }

    @objc private func pingDaemon(_ sender: Any?) {
        XPCClient.shared.ping { result in
            let alert = NSAlert()
            switch result {
            case .success(let response):
                alert.messageText = "Daemon replied"
                alert.informativeText = response
            case .failure(let error):
                alert.alertStyle = .warning
                alert.messageText = "Daemon unreachable"
                alert.informativeText = "\(error)"
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func showToday(_ sender: Any?) {
        XPCClient.shared.getTodayPlan { result in
            let alert = NSAlert()
            switch result {
            case .success(let plan):
                alert.messageText = "Today (\(plan.items.count) items)"
                if plan.items.isEmpty {
                    alert.informativeText = "Nothing scheduled. (Empty DB — expected for sub-plan #2.)"
                } else {
                    alert.informativeText = plan.items.map { "• \($0.title)" }.joined(separator: "\n")
                }
            case .failure(let error):
                alert.alertStyle = .warning
                alert.messageText = "Failed"
                alert.informativeText = "\(error)"
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
