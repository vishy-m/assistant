import Foundation
import AssistantShared

@MainActor
final class BriefingClient: NSObject, AssistantEventsProtocol {

    static let shared = BriefingClient()

    private let listener = NSXPCListener.anonymous()
    private let delegate = ListenerDelegate()

    private override init() {
        super.init()
        listener.delegate = delegate
        delegate.service = self
        listener.resume()
    }

    var endpoint: NSXPCListenerEndpoint { listener.endpoint }

    func briefingReady(_ data: Data, reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            guard let payload = try? JSONDecoder().decode(BriefingPayload.self, from: data) else {
                reply(false); return
            }
            BriefingHandler.shared.handle(payload)
            reply(true)
        }
    }

    private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
        weak var service: BriefingClient?
        func listener(_ listener: NSXPCListener,
                      shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
            newConnection.exportedInterface = NSXPCInterface(with: AssistantEventsProtocol.self)
            newConnection.exportedObject = service
            newConnection.resume()
            return true
        }
    }
}
