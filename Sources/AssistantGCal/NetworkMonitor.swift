import Foundation
import Network

public final class NetworkMonitor: @unchecked Sendable {

    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.vishruth.assistant.netmon")
    private var _isOnline: Bool = true
    private let lock = NSLock()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self._isOnline = (path.status == .satisfied)
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    public var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isOnline
    }
}
