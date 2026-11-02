import XCTest
@testable import AssistantGCal
@testable import AssistantLLM   // for SecretStore

final class GCalAuthStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCalAuthStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> GCalAuthStore {
        GCalAuthStore(secrets: SecretStore(fileURL: dir.appendingPathComponent(".env")))
    }

    func testStoreAndLoad() throws {
        let store = makeStore()
        try store.setRefreshToken("rt-abc")
        XCTAssertEqual(try store.refreshToken(), "rt-abc")
    }

    func testClear() throws {
        let store = makeStore()
        try store.setRefreshToken("rt")
        try store.clear()
        XCTAssertNil(try store.refreshToken())
    }
}
