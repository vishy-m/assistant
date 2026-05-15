import Foundation

public struct GradingScale: Equatable {

    public static let `default`: GradingScale = .init(cutoffs: [
        "A": 93, "A-": 90,
        "B+": 87, "B": 83, "B-": 80,
        "C+": 77, "C": 73, "C-": 70,
        "D+": 67, "D": 63, "D-": 60
    ])

    /// Letter → minimum percentage to earn it.
    public let cutoffs: [String: Double]

    public init(cutoffs: [String: Double]) { self.cutoffs = cutoffs }

    public func letter(for score: Double) -> String {
        let sorted = cutoffs.sorted { $0.value > $1.value }
        for (letter, min) in sorted where score >= min {
            return letter
        }
        return "F"
    }

    public func minimum(forLetter letter: String) -> Double? {
        cutoffs[letter]
    }

    public func meetsOrExceeds(current: Double, target: String) -> Bool {
        guard let min = cutoffs[target] else { return false }
        return current >= min
    }
}
