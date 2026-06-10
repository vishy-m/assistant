import XCTest
@testable import AssistantStore

final class EventTypeRepositoryTests: XCTestCase {

    func testSeedsFourBuiltins() throws {
        let db = try InMemoryDB.make()
        let repo = EventTypeRepository(db: db)
        let ids = try repo.all().map(\.id).sorted()
        XCTAssertEqual(ids, ["class", "discussion", "exam", "office_hours"])
        XCTAssertEqual(try repo.find(id: "exam")?.googleColorId, "11")
    }

    func testCreateAndDeleteCustomType() throws {
        let db = try InMemoryDB.make()
        let repo = EventTypeRepository(db: db)
        try repo.upsert(EventType(id: "lab", name: "Lab", colorHex: "0B8043",
                                  googleColorId: "10", symbolName: "flask",
                                  isBuiltin: false, sortOrder: 10))
        XCTAssertNotNil(try repo.find(id: "lab"))
        try repo.delete(id: "lab")
        XCTAssertNil(try repo.find(id: "lab"))
    }

    func testBuiltinCannotBeDeleted() throws {
        let db = try InMemoryDB.make()
        let repo = EventTypeRepository(db: db)
        try repo.delete(id: "class")
        XCTAssertNotNil(try repo.find(id: "class"))
    }

    func testUpsertRecolorsBuiltinButPreservesBuiltinFlag() throws {
        let db = try InMemoryDB.make()
        let repo = EventTypeRepository(db: db)
        // Attempt to recolor "class" AND sneak isBuiltin:false.
        try repo.upsert(EventType(id: "class", name: "Class", colorHex: "FFFFFF",
                                  googleColorId: "8", symbolName: "book.closed",
                                  isBuiltin: false, sortOrder: 0))
        let updated = try repo.find(id: "class")
        XCTAssertEqual(updated?.colorHex, "FFFFFF")   // recolor took effect
        XCTAssertEqual(updated?.isBuiltin, true)       // builtin flag preserved
        // And it still cannot be deleted.
        try repo.delete(id: "class")
        XCTAssertNotNil(try repo.find(id: "class"))
    }
}
