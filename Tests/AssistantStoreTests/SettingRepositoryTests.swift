import XCTest
@testable import AssistantStore

final class SettingRepositoryTests: XCTestCase {

    func testWriteAndReadString() throws {
        let db = try InMemoryDB.make()
        let repo = SettingRepository(db: db)

        try repo.set("morning_briefing_time", value: "08:00")
        let got: String? = try repo.get("morning_briefing_time")

        XCTAssertEqual(got, "08:00")
    }

    func testWriteAndReadCodable() throws {
        struct LeadTimes: Codable, Equatable {
            let exam: [Int]
            let assignment_due: [Int]
        }
        let db = try InMemoryDB.make()
        let repo = SettingRepository(db: db)

        let original = LeadTimes(exam: [1440, 60], assignment_due: [720, 60])
        try repo.setCodable("lead_times", value: original)
        let got: LeadTimes? = try repo.getCodable("lead_times")

        XCTAssertEqual(got, original)
    }

    func testReadMissingReturnsNil() throws {
        let db = try InMemoryDB.make()
        let repo = SettingRepository(db: db)
        let got: String? = try repo.get("nope")
        XCTAssertNil(got)
    }

    func testOverwrite() throws {
        let db = try InMemoryDB.make()
        let repo = SettingRepository(db: db)
        try repo.set("k", value: "v1")
        try repo.set("k", value: "v2")
        XCTAssertEqual(try repo.get("k") as String?, "v2")
    }
}
