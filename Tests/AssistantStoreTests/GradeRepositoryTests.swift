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

    func testCategoryWeightMustBeFiniteAndInsideZeroToOneHundred() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        let repo = GradeRepository(db: db)

        for weight in [1e20, Double.infinity, Double.nan, -1.0, 100.5] {
            XCTAssertThrowsError(try repo.insertCategory(category("bad", courseId: courseId, weight: weight))) { error in
                XCTAssertEqual(error as? GradeWriteError, .weightOutOfRange)
            }
        }
        try repo.insertCategory(category("g30", courseId: courseId, weight: 30))
        try repo.insertCategory(category("g0", courseId: courseId, weight: 0))
        let saved = try repo.categories(forCourse: courseId)
        XCTAssertEqual(saved.first { $0.id == "g30" }?.weightPct, 30)
        XCTAssertEqual(saved.first { $0.id == "g0" }?.weightPct, 0)

        var stored = try XCTUnwrap(saved.first { $0.id == "g30" })
        stored.weightPct = 1e20
        XCTAssertThrowsError(try repo.updateCategory(stored)) { error in
            XCTAssertEqual(error as? GradeWriteError, .weightOutOfRange)
        }
        XCTAssertEqual(try repo.categories(forCourse: courseId).first { $0.id == "g30" }?.weightPct, 30)
    }

    func testRegularItemRejectsNonPositiveOrNonFinitePoints() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        let repo = GradeRepository(db: db)
        try repo.insertCategory(category("g1", courseId: courseId, weight: 100))

        for maxPoints in [0.0, -5.0, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try repo.insertItem(item("bad", courseId: courseId, categoryId: "g1",
                                                           maxPoints: maxPoints, earned: 1))) { error in
                XCTAssertTrue(error is GradeWriteError)
            }
        }
        XCTAssertThrowsError(try repo.insertItem(item("nan-max", courseId: courseId, categoryId: "g1",
                                                       maxPoints: .nan, earned: 1))) { error in
            XCTAssertEqual(error as? GradeWriteError, .nonFinitePoints)
        }
        XCTAssertThrowsError(try repo.insertItem(item("nan-earned", courseId: courseId, categoryId: "g1",
                                                       maxPoints: 10, earned: .nan))) { error in
            XCTAssertEqual(error as? GradeWriteError, .nonFinitePoints)
        }
        XCTAssertThrowsError(try repo.insertItem(item("xc", courseId: courseId, categoryId: nil,
                                                       maxPoints: 0, earned: 5, extra: true))) { error in
            XCTAssertEqual(error as? GradeWriteError, .maxPointsNotPositive)
        }
        XCTAssertEqual(try repo.items(forCourse: courseId).count, 0)

        try repo.insertItem(item("ok", courseId: courseId, categoryId: "g1", maxPoints: 10, earned: 0))
        XCTAssertEqual(try repo.findItem(id: "ok")?.maxPoints, 10)

        var stored = try XCTUnwrap(repo.findItem(id: "ok"))
        stored.maxPoints = 0
        XCTAssertThrowsError(try repo.updateItem(stored))
        XCTAssertEqual(try repo.findItem(id: "ok")?.maxPoints, 10)
    }

    func testUpdateItemRejectsCourseChange() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        try CourseRepository(db: db).insert(Course(
            id: "c2", name: "Algo", term: nil, color: nil,
            targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        let repo = GradeRepository(db: db)
        try repo.insertCategory(category("g1", courseId: courseId, weight: 100))
        try repo.insertItem(item("i1", courseId: courseId, categoryId: "g1", maxPoints: 100, earned: 92))

        var moved = try XCTUnwrap(repo.findItem(id: "i1"))
        moved.courseId = "c2"
        moved.name = "moved"
        XCTAssertThrowsError(try repo.updateItem(moved)) { error in
            XCTAssertEqual(error as? GradeWriteError, .courseChangeRejected)
        }
        let stored = try repo.findItem(id: "i1")
        XCTAssertEqual(stored?.courseId, courseId)
        XCTAssertEqual(stored?.name, "HW1")
    }

    func testDeleteCategoryThrowsWhileAnItemReferencesIt() throws {
        let db = try InMemoryDB.make()
        let courseId = try makeCourse(db)
        let repo = GradeRepository(db: db)
        try repo.insertCategory(category("g1", courseId: courseId, weight: 40))
        try repo.insertCategory(category("g2", courseId: courseId, weight: 60))
        try repo.insertItem(item("i1", courseId: courseId, categoryId: "g1", maxPoints: 100, earned: 90))

        XCTAssertThrowsError(try repo.deleteCategory(id: "g1")) { error in
            XCTAssertEqual(error as? GradeWriteError, .categoryInUse)
        }
        XCTAssertNotNil(try repo.findItem(id: "i1"))
        XCTAssertEqual(try repo.categories(forCourse: courseId).count, 2)

        try repo.deleteCategory(id: "g2")
        XCTAssertEqual(try repo.categories(forCourse: courseId).map(\.id), ["g1"])
    }

    private func category(_ id: String, courseId: String, weight: Double) -> GradeCategory {
        GradeCategory(id: id, courseId: courseId, name: "HW",
                      weightPct: weight, dropLowestN: 0, dropHighestN: 0)
    }

    private func item(_ id: String, courseId: String, categoryId: String?,
                      maxPoints: Double, earned: Double?, extra: Bool = false) -> GradeItem {
        GradeItem(id: id, courseId: courseId, categoryId: categoryId,
                  name: "HW1", maxPoints: maxPoints, earnedPoints: earned,
                  dueAt: nil, isExtraCredit: extra, weightOverridePct: nil)
    }
}
