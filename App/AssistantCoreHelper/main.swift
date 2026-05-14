import Foundation
import AssistantShared

// MARK: - Listener delegate

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: AssistantService

    init(service: AssistantService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = {
            NSLog("[AssistantCoreHelper] connection invalidated")
        }
        newConnection.interruptionHandler = {
            NSLog("[AssistantCoreHelper] connection interrupted")
        }
        newConnection.resume()
        return true
    }
}

// MARK: - Bootstrap

NSLog("[AssistantCoreHelper] starting, machServiceName=\(XPCConstants.machServiceName)")

let service = AssistantService()
let delegate = ListenerDelegate(service: service)

// When launched by launchd via MachServices, this initializer attaches to the
// endpoint launchd has already created on our behalf.
let listener = NSXPCListener(machServiceName: XPCConstants.machServiceName)
listener.delegate = delegate
listener.resume()

NSLog("[AssistantCoreHelper] listener resumed, blocking on main run loop")
RunLoop.main.run()
