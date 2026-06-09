import XCTest
@testable import AssistantGCal
@testable import AssistantLLM   // for KeychainStore

final class GCalAuthStoreTests: XCTestCase {

    private let service = "com.vishruth.assistant.tests.gcal"

    override func tearDown() async throws {
        try KeychainStore(service: service).deleteAll()
    }

    func testStoreAndLoad() throws {
        let store = GCalAuthStore(keychain: KeychainStore(service: service))
        try store.setRefreshToken("rt-abc")
        XCTAssertEqual(try store.refreshToken(), "rt-abc")
    }

    func testClear() throws {
        let store = GCalAuthStore(keychain: KeychainStore(service: service))
        try store.setRefreshToken("rt")
        try store.clear()
        XCTAssertNil(try store.refreshToken())
    }
}
