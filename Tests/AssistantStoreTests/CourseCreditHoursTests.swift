import XCTest
import GRDB
@testable import AssistantStore

final class CourseCreditHoursTests: XCTestCase {
    func testCreditHoursRoundTrips() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        try repo.insert(Course(id: "c1", name: "OS", term: "Sp26", color: nil,
                               targetGrade: "A", gradingScaleJson: nil,
                               syllabusSourcePath: nil, creditHours: 3))
        let fetched = try repo.find(id: "c1")
        XCTAssertEqual(fetched?.creditHours, 3)
    }

    func testCreditHoursDefaultsToNil() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        try repo.insert(Course(id: "c2", name: "Math", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil,
                               syllabusSourcePath: nil))
        XCTAssertNil(try repo.find(id: "c2")?.creditHours)
    }
}
