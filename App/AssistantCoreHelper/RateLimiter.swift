import Foundation

/// A sliding-window rate limiter. Thread-safe; the daemon shares one instance
/// across XPC calls, which all land on background queues.
final class RateLimiter: @unchecked Sendable {

    private let lock = NSLock()
    private var timestamps: [Date] = []
    private let limit: Int
    private let window: TimeInterval

    init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Records an attempt and returns whether it is within the limit.
    func allow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        timestamps.removeAll { now.timeIntervalSince($0) >= window }
        guard timestamps.count < limit else { return false }
        timestamps.append(now)
        return true
    }
}
