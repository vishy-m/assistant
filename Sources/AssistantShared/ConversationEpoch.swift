import Foundation

/// Identifies one conversation lifetime. Reset/clear/new-conversation bumps it;
/// an async reply captured under an older value is dropped so it cannot
/// resurrect a cleared or replaced conversation.
public struct ConversationEpoch: Equatable, Sendable {
    public private(set) var current: UInt64 = 0

    public init() {}

    public mutating func bump() { current &+= 1 }

    public func isCurrent(_ epoch: UInt64) -> Bool { epoch == current }

    /// Runs `body` only if `epoch` is still current. Returns whether it ran.
    @discardableResult
    public func apply(_ epoch: UInt64, _ body: () -> Void) -> Bool {
        guard isCurrent(epoch) else { return false }
        body()
        return true
    }
}

/// Decides whether a resign-key on the overlay panel is a real dismissal.
public enum CropDismissGate {
    /// Dismiss only when we are not hiding the panel for a crop selection and
    /// the panel has not become key again by the time the delayed check runs.
    public static func shouldDismiss(suspended: Bool, isKey: Bool) -> Bool {
        !suspended && !isKey
    }
}
