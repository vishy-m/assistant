import XCTest
@testable import AssistantGrades
@testable import AssistantStore
@testable import AssistantLLM

final class GradeToolsTests: XCTestCase {

    func testEnterGradeToolUpdatesItem() async throws {
        let db = try InMemoryDB.make()
        try CourseRepository(db: db).insert(Course(
            id: "c1", name: "OS", term: nil, color: nil,
            targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        let gradeRepo = GradeRepository(db: db)
        try gradeRepo.insertCategory(GradeCategory(
            id: "g1", courseId: "c1", name: "HW", weightPct: 100,
            dropLowestN: 0, dropHighestN: 0))
        try gradeRepo.insertItem(GradeItem(
            id: "i1", courseId: "c1", categoryId: "g1",
            name: "HW1", maxPoints: 100, earnedPoints: nil,
            dueAt: nil, isExtraCredit: false, weightOverridePct: nil))

        var registry = ToolRegistry()
        GradeTools.register(into: &registry, db: db)

        let result = try await registry.invoke(name: "enter_grade",
                                               argumentsJSON: #"{"item_id":"i1","earned_points":92}"#)
        XCTAssertTrue(result.contains("updated"))
        XCTAssertEqual(try gradeRepo.findItem(id: "i1")?.earnedPoints, 92)
    }

    func testComputeGradeTool() async throws {
        let db = try InMemoryDB.make()
        try CourseRepository(db: db).insert(Course(
            id: "c1", name: "OS", term: nil, color: nil,
            targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        let gradeRepo = GradeRepository(db: db)
        try gradeRepo.insertCategory(GradeCategory(
            id: "g1", courseId: "c1", name: "HW", weightPct: 100,
            dropLowestN: 0, dropHighestN: 0))
        try gradeRepo.insertItem(GradeItem(
            id: "i1", courseId: "c1", categoryId: "g1",
            name: "HW1", maxPoints: 100, earnedPoints: 90,
            dueAt: nil, isExtraCredit: false, weightOverridePct: nil))

        var registry = ToolRegistry()
        GradeTools.register(into: &registry, db: db)

        let result = try await registry.invoke(name: "compute_grade",
                                               argumentsJSON: #"{"course_id":"c1"}"#)
        XCTAssertTrue(result.contains("\"current_pct\":90"))
    }
}
