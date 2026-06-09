import XCTest
@testable import AssistantBriefings
@testable import AssistantStore

final class BriefingRulesTests: XCTestCase {

    func testClusteredDeadlinesWithoutStudyBlocks() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        let now = Date()
        for i in 0..<4 {
            try repo.insert(AssistantStore.Task(
                id: "t\(i)", title: "T\(i)", notes: nil,
                dueAt: now.addingTimeInterval(Double(i + 1) * 3600 * 6),
                completedAt: nil, courseId: nil, gradeItemId: nil,
                priority: 0, category: "assignment_due", source: "manual"))
        }
        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertTrue(findings.contains { $0.kind == .clusteredDeadlines })
    }

    func testAssignmentDueSoonIncomplete() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        let now = Date()
        try repo.insert(AssistantStore.Task(
            id: "t1", title: "HW1", notes: nil,
            dueAt: now.addingTimeInterval(3600 * 12),
            completedAt: nil, courseId: nil, gradeItemId: nil,
            priority: 0, category: "assignment_due", source: "parsed"))
        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertTrue(findings.contains { $0.kind == .assignmentDueSoon })
    }

    func testCompletedTaskNotFlagged() throws {
        let db = try InMemoryDB.make()
        let repo = TaskRepository(db: db)
        let now = Date()
        try repo.insert(AssistantStore.Task(
            id: "t1", title: "HW1", notes: nil,
            dueAt: now.addingTimeInterval(3600 * 12),
            completedAt: now, courseId: nil, gradeItemId: nil,
            priority: 0, category: "assignment_due", source: "parsed"))
        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertFalse(findings.contains { $0.kind == .assignmentDueSoon })
    }
}
