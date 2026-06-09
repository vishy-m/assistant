import XCTest
@testable import AssistantStore

final class BriefingRepositoryTests: XCTestCase {

    func testInsertAndQueryByKind() throws {
        let db = try InMemoryDB.make()
        let repo = BriefingRepository(db: db)
        try repo.insert(Briefing(
            id: "b1", kind: "morning", firedAt: Date(),
            payloadJson: "{}", dismissedAt: nil, actedOn: false))
        try repo.insert(Briefing(
            id: "b2", kind: "evening", firedAt: Date(),
            payloadJson: "{}", dismissedAt: nil, actedOn: false))

        XCTAssertEqual(try repo.recent(kind: "morning", limit: 5).count, 1)
        XCTAssertEqual(try repo.recent(kind: nil, limit: 5).count, 2)
    }

    func testMarkDismissed() throws {
        let db = try InMemoryDB.make()
        let repo = BriefingRepository(db: db)
        try repo.insert(Briefing(
            id: "b1", kind: "risk", firedAt: Date(),
            payloadJson: "{}", dismissedAt: nil, actedOn: false))
        try repo.markDismissed(id: "b1")
        XCTAssertNotNil(try repo.find(id: "b1")?.dismissedAt)
    }
}
