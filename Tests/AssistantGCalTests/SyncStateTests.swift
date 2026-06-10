import XCTest
@testable import AssistantGCal
@testable import AssistantStore

final class SyncStateTests: XCTestCase {

    func testStoreAndLoad() throws {
        let db = try InMemoryDB.make()
        let state = SyncState(db: db)
        try state.setSyncToken("primary", token: "TOK1")
        try state.setSyncToken("school", token: "TOK2")
        XCTAssertEqual(try state.syncToken(for: "primary"), "TOK1")
        XCTAssertEqual(try state.syncToken(for: "school"), "TOK2")
        XCTAssertNil(try state.syncToken(for: "missing"))
    }

    func testClear() throws {
        let db = try InMemoryDB.make()
        let state = SyncState(db: db)
        try state.setSyncToken("primary", token: "T")
        try state.clearSyncToken("primary")
        XCTAssertNil(try state.syncToken(for: "primary"))
    }
}
