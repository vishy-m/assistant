import Foundation

/// Matches a grade load to the course selection that started it.
/// A reply from an older selection is dropped.
public struct GradeLoadGate: Equatable {
    public private(set) var generation: UInt64 = 0
    public private(set) var courseId: String?

    public init() {}

    public mutating func begin(_ courseId: String) -> UInt64 {
        generation &+= 1
        self.courseId = courseId
        return generation
    }

    public mutating func clear() -> UInt64 {
        generation &+= 1
        courseId = nil
        return generation
    }

    public func accepts(generation: UInt64, courseId: String) -> Bool {
        self.generation == generation && self.courseId == courseId
    }
}
