import Foundation
import ServiceManagement

@MainActor
final class DaemonInstaller {

    static let shared = DaemonInstaller()
    private init() {}

    private var agentService: SMAppService {
        SMAppService.agent(plistName: "com.vishruth.assistant.core.plist")
    }

    var isRegistered: Bool {
        agentService.status == .enabled
    }

    func register() async -> Bool {
        do {
            try agentService.register()
            return true
        } catch {
            NSLog("[DaemonInstaller] register failed: \(error)")
            return false
        }
    }

    func unregister() async -> Bool {
        do {
            try await agentService.unregister()
            return true
        } catch {
            NSLog("[DaemonInstaller] unregister failed: \(error)")
            return false
        }
    }

    func setLaunchAtLogin(_ on: Bool) async {
        let loginItem = SMAppService.mainApp
        do {
            if on { try loginItem.register() } else { try await loginItem.unregister() }
        } catch {
            NSLog("[DaemonInstaller] setLaunchAtLogin failed: \(error)")
        }
        if on { _ = await register() }
    }
}
