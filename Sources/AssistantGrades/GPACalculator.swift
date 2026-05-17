import Foundation

/// Credit-weighted GPA on the standard 4.0 +/- scale. Courses missing credit
/// hours, or with no graded work yet, are excluded so the number stays honest.
public enum GPACalculator {

    public static let gradePoints: [String: Double] = [
        "A": 4.0, "A-": 3.7,
        "B+": 3.3, "B": 3.0, "B-": 2.7,
        "C+": 2.3, "C": 2.0, "C-": 1.7,
        "D+": 1.3, "D": 1.0, "D-": 0.7,
        "F": 0.0
    ]

    public struct CourseGrade {
        public let letter: String
        public let creditHours: Double?
        public let hasGradedWork: Bool
        public init(letter: String, creditHours: Double?, hasGradedWork: Bool) {
            self.letter = letter
            self.creditHours = creditHours
            self.hasGradedWork = hasGradedWork
        }
    }

    public struct Result: Equatable, Codable {
        public let gpa: Double
        public let countedCourses: Int
        public let totalCourses: Int
        public init(gpa: Double, countedCourses: Int, totalCourses: Int) {
            self.gpa = gpa
            self.countedCourses = countedCourses
            self.totalCourses = totalCourses
        }
    }

    public static func compute(_ courses: [CourseGrade]) -> Result {
        let counted = courses.filter { $0.hasGradedWork && ($0.creditHours ?? 0) > 0 }
        let creditSum = counted.reduce(0.0) { $0 + ($1.creditHours ?? 0) }
        guard creditSum > 0 else {
            return Result(gpa: 0, countedCourses: 0, totalCourses: courses.count)
        }
        let weighted = counted.reduce(0.0) { acc, c in
            acc + (gradePoints[c.letter] ?? 0) * (c.creditHours ?? 0)
        }
        return Result(gpa: weighted / creditSum,
                      countedCourses: counted.count,
                      totalCourses: courses.count)
    }
}
