import Foundation

/// Thread-safe holder for the daemon's single event-client connection.
///
/// An old connection's invalidation handler can fire after a newer connection
/// was registered. It must call `clearIfSame(old)`, which only clears the slot
/// when it still holds that exact object. Generic over `AnyObject` so tests do
/// not need a live `NSXPCConnection`.
public final class EventClientSlot<Connection: AnyObject> {
    private let lock = NSLock()
    private var connection: Connection?

    public init() {}

    /// Stores `new` and returns the previous connection (if any) so the caller
    /// can invalidate it outside the lock. The new value is stored first, so a
    /// synchronous invalidation handler on the old one sees the new one.
    @discardableResult
    public func replace(_ new: Connection) -> Connection? {
        lock.lock(); defer { lock.unlock() }
        let previous = connection
        connection = new
        return previous === new ? nil : previous
    }

    /// Clears the slot only if it still holds `conn`.
    public func clearIfSame(_ conn: Connection) {
        lock.lock(); defer { lock.unlock() }
        if connection === conn { connection = nil }
    }

    /// Retained snapshot; nil if nothing is registered.
    public var current: Connection? {
        lock.lock(); defer { lock.unlock() }
        return connection
    }

    /// Runs `body` with a retained snapshot after the lock is released, so the
    /// caller may message the connection without holding the lock.
    public func withCurrent<T>(_ body: (Connection) throws -> T?) rethrows -> T? {
        guard let snapshot = current else { return nil }
        return try body(snapshot)
    }
}
