import XCTest
@testable import AssistantStore

final class CourseRepositoryTests: XCTestCase {

    func testInsertAndFetchById() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        let course = Course(id: "c1", name: "Operating Systems", term: "Spring 2026",
                            color: "#FF9933", targetGrade: "A-",
                            gradingScaleJson: nil, syllabusSourcePath: nil)
        try repo.insert(course)

        let got = try repo.find(id: "c1")
        XCTAssertEqual(got?.name, "Operating Systems")
    }

    func testListAll() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        try repo.insert(Course(id: "c1", name: "A", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        try repo.insert(Course(id: "c2", name: "B", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        XCTAssertEqual(try repo.all().count, 2)
    }

    func testDelete() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        try repo.insert(Course(id: "c1", name: "A", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        try repo.delete(id: "c1")
        XCTAssertNil(try repo.find(id: "c1"))
    }

    func testCourseRoundTripsContactFields() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        var course = Course(id: "c1", name: "OS", term: "Fall", color: "4F6B7A",
                            targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil)
        course.professorName = "Dr. Ada"
        course.professorEmail = "ada@uni.edu"
        course.classroom = "ENS 207"
        course.iconName = "book.closed"
        try repo.insert(course)

        let loaded = try repo.find(id: "c1")
        XCTAssertEqual(loaded?.professorName, "Dr. Ada")
        XCTAssertEqual(loaded?.professorEmail, "ada@uni.edu")
        XCTAssertEqual(loaded?.classroom, "ENS 207")
        XCTAssertEqual(loaded?.iconName, "book.closed")
    }
}
