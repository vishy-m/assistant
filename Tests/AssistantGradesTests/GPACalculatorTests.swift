import XCTest
@testable import AssistantGrades

final class GPACalculatorTests: XCTestCase {

    func testCreditWeightedAverage() {
        let result = GPACalculator.compute([
            .init(letter: "A",  creditHours: 3, hasGradedWork: true),
            .init(letter: "B",  creditHours: 4, hasGradedWork: true)
        ])
        XCTAssertEqual(result.gpa, 24.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(result.countedCourses, 2)
        XCTAssertEqual(result.totalCourses, 2)
    }

    func testExcludesCoursesMissingCreditHours() {
        let result = GPACalculator.compute([
            .init(letter: "A", creditHours: 3, hasGradedWork: true),
            .init(letter: "C", creditHours: nil, hasGradedWork: true)
        ])
        XCTAssertEqual(result.gpa, 4.0, accuracy: 0.0001)
        XCTAssertEqual(result.countedCourses, 1)
        XCTAssertEqual(result.totalCourses, 2)
    }

    func testExcludesCoursesWithNoGradedWork() {
        let result = GPACalculator.compute([
            .init(letter: "A", creditHours: 3, hasGradedWork: true),
            .init(letter: "F", creditHours: 3, hasGradedWork: false)
        ])
        XCTAssertEqual(result.gpa, 4.0, accuracy: 0.0001)
        XCTAssertEqual(result.countedCourses, 1)
    }

    func testNoEligibleCoursesYieldsZero() {
        let result = GPACalculator.compute([
            .init(letter: "A", creditHours: nil, hasGradedWork: true)
        ])
        XCTAssertEqual(result.gpa, 0)
        XCTAssertEqual(result.countedCourses, 0)
        XCTAssertEqual(result.totalCourses, 1)
    }

    func testPlusMinusGradePoints() {
        XCTAssertEqual(GPACalculator.gradePoints["A-"], 3.7)
        XCTAssertEqual(GPACalculator.gradePoints["B+"], 3.3)
        XCTAssertEqual(GPACalculator.gradePoints["F"], 0.0)
    }
}
