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

    func testWednesdayStudyBlockSuppressesFortyEightHourCluster() throws {
        let now = try mondayEighteenHundred()
        let db = try InMemoryDB.make()
        try insertThreeDeadlines(db: db, now: now)
        let start = now.addingTimeInterval(39 * 3600) // Wednesday 09:00
        try insertEvent(db: db, id: "wed", title: "study", start: start,
                        end: start.addingTimeInterval(3600), category: "Misc")

        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertFalse(findings.contains { $0.kind == .clusteredDeadlines })
    }

    func testEndedMondayStudyBlockDoesNotSuppressCluster() throws {
        let now = try mondayEighteenHundred()
        let db = try InMemoryDB.make()
        try insertThreeDeadlines(db: db, now: now)
        let start = now.addingTimeInterval(-10 * 3600) // Monday 08:00
        try insertEvent(db: db, id: "mon", title: "study", start: start,
                        end: start.addingTimeInterval(3600), category: "Misc")

        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertTrue(findings.contains { $0.kind == .clusteredDeadlines })
    }

    func testStudyCategorySuppressesClusterWhenTitleDoesNotMatch() throws {
        let now = try mondayEighteenHundred()
        let db = try InMemoryDB.make()
        try insertThreeDeadlines(db: db, now: now)
        let start = now.addingTimeInterval(39 * 3600)
        try insertEvent(db: db, id: "pset", title: "Problem set", start: start,
                        end: start.addingTimeInterval(3600), category: "Study")

        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertFalse(findings.contains { $0.kind == .clusteredDeadlines })
    }

    func testStudyEventTypeSuppressesClusterWhenTitleDoesNotMatch() throws {
        let now = try mondayEighteenHundred()
        let db = try InMemoryDB.make()
        try insertThreeDeadlines(db: db, now: now)
        let start = now.addingTimeInterval(39 * 3600)
        try insertEvent(db: db, id: "pset-type", title: "Problem set", start: start,
                        end: start.addingTimeInterval(3600), category: "Class", eventType: "study")

        let findings = try BriefingRules(db: db, clock: { now }).evaluate()
        XCTAssertFalse(findings.contains { $0.kind == .clusteredDeadlines })
    }

    private func mondayEighteenHundred() throws -> Date {
        let cal = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 3, day: 2, hour: 18, minute: 0, second: 0)))
        XCTAssertEqual(cal.component(.weekday, from: now), 2)
        return now
    }

    private func insertThreeDeadlines(db: AssistantDB, now: Date) throws {
        let repo = TaskRepository(db: db)
        let dues = [
            now.addingTimeInterval(2 * 3600),
            now.addingTimeInterval(18 * 3600),
            now.addingTimeInterval(42 * 3600)
        ]
        for (i, due) in dues.enumerated() {
            try repo.insert(AssistantStore.Task(
                id: "d\(i)", title: "Deadline \(i)", notes: nil,
                dueAt: due, completedAt: nil, courseId: nil, gradeItemId: nil,
                priority: 0, category: "Assignment", source: "manual"))
        }
    }

    private func insertEvent(db: AssistantDB, id: String, title: String, start: Date, end: Date,
                             category: String, eventType: String? = nil) throws {
        try GCalRepository(db: db).upsert(GCalEventCache(
            gcalEventId: id, calendarId: "primary", title: title,
            startAt: start, endAt: end, location: nil, category: category,
            lastSyncedAt: start, rawJson: "{}", eventType: eventType))
    }
}
