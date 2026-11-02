import Foundation

/// Tags each class-detail load with (course, generation) so replies from an
/// earlier load — another class, or an older load of the same class — are
/// dropped instead of overwriting the selected class's state.
public struct ClassLoadGate: Equatable, Sendable {
    public struct Token: Equatable, Sendable {
        public let courseId: String
        public let generation: UInt64
    }

    private var generation: UInt64 = 0
    public private(set) var current: Token?

    public init() {}

    /// Begins a new load for `courseId`; earlier tokens stop being accepted.
    @discardableResult
    public mutating func start(courseId: String) -> Token {
        generation &+= 1
        let token = Token(courseId: courseId, generation: generation)
        current = token
        return token
    }

    public func accepts(_ token: Token) -> Bool { token == current }
}
