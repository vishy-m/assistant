import XCTest
@testable import AssistantGCal
@testable import AssistantStore

final class QuotaGuardTests: XCTestCase {

    func testIncrementsAndAllows() throws {
        let db = try InMemoryDB.make()
        let q = QuotaGuard(db: db, cap: 5, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        XCTAssertTrue(try q.tryConsume())
        XCTAssertTrue(try q.tryConsume())
        XCTAssertEqual(try q.usedToday(), 2)
    }

    func testCapEnforced() throws {
        let db = try InMemoryDB.make()
        let q = QuotaGuard(db: db, cap: 2, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        _ = try q.tryConsume()
        _ = try q.tryConsume()
        XCTAssertFalse(try q.tryConsume())
    }

    func testNewDayResetsCount() throws {
        let db = try InMemoryDB.make()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let q = QuotaGuard(db: db, cap: 2, clock: { now })
        _ = try q.tryConsume()
        _ = try q.tryConsume()
        XCTAssertFalse(try q.tryConsume())
        // Jump 1 day forward
        now = now.addingTimeInterval(86_400 + 60)
        XCTAssertTrue(try q.tryConsume())
        XCTAssertEqual(try q.usedToday(), 1)
    }
}
