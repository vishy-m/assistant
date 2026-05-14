import Foundation
import AssistantShared
import AssistantStore

NSLog("[AssistantCoreHelper] starting, machServiceName=\(XPCConstants.machServiceName)")

let dbURL: URL
do {
    dbURL = try AssistantDB.defaultFileURL()
} catch {
    NSLog("[AssistantCoreHelper] FATAL: could not resolve DB path: \(error)")
    exit(1)
}

let db: AssistantDB
do {
    db = try AssistantDB(fileURL: dbURL)
} catch {
    NSLog("[AssistantCoreHelper] FATAL: could not open DB at \(dbURL): \(error)")
    exit(1)
}
NSLog("[AssistantCoreHelper] DB opened at \(dbURL.path)")

let service = AssistantService(db: db)

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: AssistantService
    init(service: AssistantService) { self.service = service }
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

let delegate = ListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: XPCConstants.machServiceName)
listener.delegate = delegate
listener.resume()

NSLog("[AssistantCoreHelper] listener resumed")
RunLoop.main.run()
