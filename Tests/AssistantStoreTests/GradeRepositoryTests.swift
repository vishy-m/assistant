import XCTest
@testable import AssistantStore

final class GradeRepositoryTests: XCTestCase {

    private func makeCourse(_ db: AssistantDB) throws -> String {
        let cr = CourseRepository(db: db)
        try cr.insert(Course(id: "c1", name: "OS", term: nil, color: nil,
                             targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        return "c1"
    }

    func testInsertCategoriesAndItems() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        let repo = GradeRepository(db: db)

        try repo.insertCategory(GradeCategory(
            id: "g1", courseId: courseId, name: "Homework",
            weightPct: 30, dropLowestN: 1, dropHighestN: 0))
        try repo.insertItem(GradeItem(
            id: "i1", courseId: courseId, categoryId: "g1",
            name: "HW1", maxPoints: 100, earnedPoints: 92,
            dueAt: nil, isExtraCredit: false, weightOverridePct: nil))

        XCTAssertEqual(try repo.categories(forCourse: courseId).count, 1)
        XCTAssertEqual(try repo.items(forCourse: courseId).count, 1)
        XCTAssertEqual(try repo.items(forCategory: "g1").count, 1)
    }

    func testUpdateEarnedPoints() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        let repo = GradeRepository(db: db)
        try repo.insertCategory(GradeCategory(
            id: "g1", courseId: courseId, name: "HW", weightPct: 100,
            dropLowestN: 0, dropHighestN: 0))
        try repo.insertItem(GradeItem(
            id: "i1", courseId: courseId, categoryId: "g1",
            name: "HW1", maxPoints: 100, earnedPoints: nil,
            dueAt: nil, isExtraCredit: false, weightOverridePct: nil))

        try repo.setEarnedPoints(itemId: "i1", earned: 88)
        XCTAssertEqual(try repo.findItem(id: "i1")?.earnedPoints, 88)
    }

    func testCascadeDeleteOnCourse() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        let repo = GradeRepository(db: db)
        try repo.insertCategory(GradeCategory(
            id: "g1", courseId: courseId, name: "HW", weightPct: 100,
            dropLowestN: 0, dropHighestN: 0))
        try repo.insertItem(GradeItem(
            id: "i1", courseId: courseId, categoryId: "g1",
            name: "HW1", maxPoints: 100, earnedPoints: nil,
            dueAt: nil, isExtraCredit: false, weightOverridePct: nil))

        try CourseRepository(db: db).delete(id: courseId)
        XCTAssertEqual(try repo.categories(forCourse: courseId).count, 0)
        XCTAssertEqual(try repo.items(forCourse: courseId).count, 0)
    }
}
