import Foundation
@testable import AssistantShared

/// In-process XPC harness for testing AssistantServiceProtocol round-trips
/// without requiring launchd, code signing, or a separate process.
///
/// Uses NSXPCListener.anonymous(), which exposes an endpoint usable from the
/// same process via NSXPCConnection(listenerEndpoint:).
final class InProcessXPCHarness {

    private let listener: NSXPCListener
    private let connection: NSXPCConnection
    private let delegate: ListenerDelegate

    let proxy: AssistantServiceProtocol

    init(service: AssistantServiceProtocol) throws {
        let listener = NSXPCListener.anonymous()
        let delegate = ListenerDelegate(service: service)
        listener.delegate = delegate
        listener.resume()

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ err in
            // Surfaced into the test via timeout — the call site uses an expectation.
            print("[InProcessXPCHarness] remote proxy error: \(err)")
        }) as? AssistantServiceProtocol else {
            throw NSError(domain: "InProcessXPCHarness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "proxy cast failed"])
        }

        self.listener = listener
        self.connection = connection
        self.delegate = delegate
        self.proxy = proxy
    }

    func invalidate() {
        connection.invalidate()
        listener.invalidate()
    }

    /// Holds the exported object alive and wires it onto each new connection.
    private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
        private let service: AssistantServiceProtocol
        init(service: AssistantServiceProtocol) { self.service = service }

        func listener(_ listener: NSXPCListener,
                      shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
            newConnection.exportedInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
            newConnection.exportedObject = service
            newConnection.resume()
            return true
        }
    }
}
