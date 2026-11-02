import Foundation

/// Exactly-once completion bookkeeping for XPC calls, plus connection identity
/// and briefing re-registration state. Pure and thread-safe so the UI's
/// `XPCClient` can delegate its lifecycle rules here and they can be tested.
///
/// - Each connection gets a fresh `generation` from `beginConnection()`.
/// - Each call `register`s a failure closure against its connection's
///   generation before the message is sent.
/// - Whichever comes first wins: the reply (`complete`) or the connection
///   failure (`failAll`). The loser is a no-op, so a caller's reply or
///   continuation runs exactly once.
/// - `endConnection(generation:)` only clears the current connection when the
///   generation still matches, so a dead connection's late handler cannot tear
///   down its replacement.
public final class XPCCallGate: @unchecked Sendable {

    public typealias CallID = UInt64

    private let lock = NSLock()
    private var nextGeneration: UInt64 = 0
    private var current: UInt64?
    private var nextCallID: CallID = 0
    private var pending: [CallID: (generation: UInt64, onFailure: () -> Void)] = [:]

    private var dirty = false
    private var reregisterInFlight = false
    private var dirtiedWhileInFlight = false

    public init() {}

    // MARK: Connection identity

    /// Starts a new connection generation and makes it current.
    @discardableResult
    public func beginConnection() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        nextGeneration += 1
        current = nextGeneration
        return nextGeneration
    }

    /// The live connection's generation, or nil when none is open.
    public var currentGeneration: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Clears the current connection only if `generation` is still current.
    /// Returns false (and changes nothing) for a stale generation.
    @discardableResult
    public func endConnection(generation: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard current == generation else { return false }
        current = nil
        return true
    }

    // MARK: Calls

    /// Records an outstanding call. `onFailure` runs at most once, and only if
    /// the call's generation fails before `complete` is called.
    public func register(generation: UInt64, onFailure: @escaping () -> Void) -> CallID {
        lock.lock(); defer { lock.unlock() }
        nextCallID += 1
        pending[nextCallID] = (generation, onFailure)
        return nextCallID
    }

    /// Marks a call as answered. True the first time only; false if the call
    /// was already completed or failed.
    @discardableResult
    public func complete(_ id: CallID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pending.removeValue(forKey: id) != nil
    }

    /// Fails every outstanding call of `generation` (and no other), running
    /// each failure closure once, outside the lock. Returns how many ran.
    @discardableResult
    public func failAll(generation: UInt64) -> Int {
        lock.lock()
        let ids = pending.filter { $0.value.generation == generation }.map(\.key)
        let failures = ids.compactMap { pending.removeValue(forKey: $0)?.onFailure }
        lock.unlock()
        failures.forEach { $0() }
        return failures.count
    }

    // MARK: Event-client re-registration

    /// True when the daemon may not hold our event endpoint.
    public var needsReregister: Bool {
        lock.lock(); defer { lock.unlock() }
        return dirty
    }

    /// The registration was lost (connection failed) or never made.
    public func markNeedsReregister() {
        lock.lock(); defer { lock.unlock() }
        dirty = true
        if reregisterInFlight { dirtiedWhileInFlight = true }
    }

    /// True if the caller should send the registration now. Only one
    /// registration is in flight at a time.
    public func beginReregister() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard dirty, !reregisterInFlight else { return false }
        reregisterInFlight = true
        dirtiedWhileInFlight = false
        return true
    }

    /// Records the in-flight registration's outcome. A success only clears the
    /// flag if no connection loss happened while it was in flight.
    public func recordReregister(success: Bool) {
        lock.lock(); defer { lock.unlock() }
        reregisterInFlight = false
        dirty = !success || dirtiedWhileInFlight
        dirtiedWhileInFlight = false
    }
}
