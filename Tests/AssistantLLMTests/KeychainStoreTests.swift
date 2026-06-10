import XCTest
@testable import AssistantLLM

final class KeychainStoreTests: XCTestCase {

    private let testService = "com.vishruth.assistant.tests"

    override func tearDown() async throws {
        try KeychainStore(service: testService).deleteAll()
    }

    func testWriteThenRead() throws {
        let store = KeychainStore(service: testService)
        try store.set(account: "claude_api_key", value: "sk-test-123")
        XCTAssertEqual(try store.get(account: "claude_api_key"), "sk-test-123")
    }

    func testOverwrite() throws {
        let store = KeychainStore(service: testService)
        try store.set(account: "k", value: "v1")
        try store.set(account: "k", value: "v2")
        XCTAssertEqual(try store.get(account: "k"), "v2")
    }

    func testMissingReturnsNil() throws {
        let store = KeychainStore(service: testService)
        XCTAssertNil(try store.get(account: "nope"))
    }

    func testDeleteRemoves() throws {
        let store = KeychainStore(service: testService)
        try store.set(account: "k", value: "v")
        try store.delete(account: "k")
        XCTAssertNil(try store.get(account: "k"))
    }
}
