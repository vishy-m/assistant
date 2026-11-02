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

    /// Letters a stored scale may define; anything else in the JSON is ignored.
    static let knownLetters: Set<String> = [
        "A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-"
    ]

    /// Parses `Course.gradingScaleJson` (`{"A": 93, "A-": 90, ...}`). nil, blank,
    /// invalid JSON, a non-numeric cutoff, or no known letters all fall back to
    /// `.default` so a bad scale only affects letters, never the grade read.
    public static func parse(json: String?) -> GradingScale {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return .default }
        guard raw.values.allSatisfy({ $0.isFinite }) else { return .default }
        let cutoffs = raw.filter { knownLetters.contains($0.key) }
        return cutoffs.isEmpty ? .default : GradingScale(cutoffs: cutoffs)
    }

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
