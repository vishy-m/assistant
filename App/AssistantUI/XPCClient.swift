import Foundation
import AssistantShared

/// Wraps NSXPCConnection to the daemon. All future XPC calls go through here.
///
/// Connection lifecycle: lazily created on first use, kept alive for the
/// process lifetime, recreated automatically if it invalidates.
final class XPCClient {

    static let shared = XPCClient()

    private let queue = DispatchQueue(label: "com.vishruth.assistant.xpcclient")
    private var connection: NSXPCConnection?

    private init() {}

    /// Calls `ping` on the daemon. `reply` is called on `DispatchQueue.main`.
    func ping(reply: @escaping (Result<String, Error>) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.ping { response in
                DispatchQueue.main.async { reply(.success(response)) }
            }
        } catch {
            DispatchQueue.main.async { reply(.failure(error)) }
        }
    }

    /// Calls `getTodayPlan` and decodes the JSON response. Reply on main queue.
    func getTodayPlan(reply: @escaping (Result<TodayPlan, Error>) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.getTodayPlan { data in
                DispatchQueue.main.async {
                    guard !data.isEmpty else {
                        reply(.failure(XPCClientError.emptyResponse))
                        return
                    }
                    do {
                        let plan = try JSONDecoder().decode(TodayPlan.self, from: data)
                        reply(.success(plan))
                    } catch {
                        reply(.failure(error))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { reply(.failure(error)) }
        }
    }

    // MARK: - Connection management

    private func makeProxy() throws -> AssistantServiceProtocol {
        let conn = currentConnection()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] err in
            NSLog("[XPCClient] remote proxy error: \(err)")
            self?.invalidate()
        }) as? AssistantServiceProtocol else {
            throw XPCClientError.proxyCastFailed
        }
        return proxy
    }

    private func currentConnection() -> NSXPCConnection {
        queue.sync {
            if let existing = connection { return existing }

            // .privileged is NOT used: this is a user-level LaunchAgent, not a daemon.
            let conn = NSXPCConnection(machServiceName: XPCConstants.machServiceName,
                                       options: [])
            conn.remoteObjectInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
            conn.invalidationHandler = { [weak self] in
                NSLog("[XPCClient] connection invalidated")
                self?.invalidate()
            }
            conn.interruptionHandler = {
                NSLog("[XPCClient] connection interrupted (daemon crashed?)")
            }
            conn.resume()
            self.connection = conn
            return conn
        }
    }

    private func invalidate() {
        queue.sync {
            connection?.invalidate()
            connection = nil
        }
    }
}

enum XPCClientError: Error {
    case proxyCastFailed
    case emptyResponse
}
