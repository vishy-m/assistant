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
        menu.addItem(NSMenuItem(title: "Submit prompt…",
                                action: #selector(submitPromptDev(_:)),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Connect Google Calendar…",
                                action: #selector(connectGoogle(_:)),
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

    @objc private func submitPromptDev(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Submit prompt (dev)"
        alert.informativeText = "Type a natural-language prompt. The daemon will run it through the LLM chain."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              !field.stringValue.isEmpty else { return }

        let text = field.stringValue
        XPCClient.shared.submitPrompt(text: text) { result in
            let resultAlert = NSAlert()
            switch result {
            case .success(let resp) where resp.errorMessage == nil:
                resultAlert.messageText = "Reply via \(resp.modelUsed)"
                resultAlert.informativeText = resp.text.isEmpty ? "(no text content — likely tool calls only)" : resp.text
            case .success(let resp):
                resultAlert.alertStyle = .warning
                resultAlert.messageText = "Chain error"
                resultAlert.informativeText = resp.errorMessage ?? "unknown"
            case .failure(let err):
                resultAlert.alertStyle = .warning
                resultAlert.messageText = "XPC failed"
                resultAlert.informativeText = "\(err)"
            }
            resultAlert.addButton(withTitle: "OK")
            resultAlert.runModal()
        }
    }

    @objc private func connectGoogle(_ sender: Any?) {
        let win = NSApp.keyWindow ?? NSWindow()
        Task { @MainActor in
            await GoogleAuthFlow.shared.connect(presentingWindow: win)
        }
    }
}
