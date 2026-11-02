import XCTest
@testable import AssistantLLM

final class SecretStoreTests: XCTestCase {

    private var dir: URL!
    private var envURL: URL { dir.appendingPathComponent(".env") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecretStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileReadsAsNil() throws {
        XCTAssertNil(try SecretStore(fileURL: envURL).get(.claudeAPIKey))
    }

    func testWriteThenRead() throws {
        let store = SecretStore(fileURL: envURL)
        try store.set(.claudeAPIKey, value: "sk-test-123")
        XCTAssertEqual(try store.get(.claudeAPIKey), "sk-test-123")
        let text = try String(contentsOf: envURL, encoding: .utf8)
        XCTAssertTrue(text.contains("ANTHROPIC_API_KEY=sk-test-123"))
    }

    func testOverwrite() throws {
        let store = SecretStore(fileURL: envURL)
        try store.set(.openaiAPIKey, value: "v1")
        try store.set(.openaiAPIKey, value: "v2")
        XCTAssertEqual(try store.get(.openaiAPIKey), "v2")
    }

    func testDeleteRemoves() throws {
        let store = SecretStore(fileURL: envURL)
        try store.set(.gemmaHostedAPIKey, value: "v")
        try store.delete(.gemmaHostedAPIKey)
        XCTAssertNil(try store.get(.gemmaHostedAPIKey))
    }

    func testEmptyValueReadsAsNil() throws {
        try "ANTHROPIC_API_KEY=\n".write(to: envURL, atomically: true, encoding: .utf8)
        XCTAssertNil(try SecretStore(fileURL: envURL).get(.claudeAPIKey))
    }

    func testHandEditedFileIsPickedUpWithoutRestart() throws {
        let store = SecretStore(fileURL: envURL)
        try store.set(.claudeAPIKey, value: "old")
        try "ANTHROPIC_API_KEY=edited\n".write(to: envURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.get(.claudeAPIKey), "edited")
    }

    func testWritePreservesUserComments() throws {
        try "# my keys\nOPENAI_API_KEY=o\n".write(to: envURL, atomically: true, encoding: .utf8)
        try SecretStore(fileURL: envURL).set(.claudeAPIKey, value: "c")
        XCTAssertEqual(try String(contentsOf: envURL, encoding: .utf8),
                       "# my keys\nOPENAI_API_KEY=o\nANTHROPIC_API_KEY=c\n")
    }

    func testWrittenFileIsOwnerOnly() throws {
        try SecretStore(fileURL: envURL).set(.claudeAPIKey, value: "c")
        let attrs = try FileManager.default.attributesOfItem(atPath: envURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testWriteThroughSymlinkKeepsTheSymlink() throws {
        let shared = dir.appendingPathComponent("shared.env")
        try "".write(to: shared, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: envURL, withDestinationURL: shared)

        try SecretStore(fileURL: envURL).set(.claudeAPIKey, value: "c")

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: envURL.path),
                       shared.path)
        XCTAssertEqual(try SecretStore(fileURL: shared).get(.claudeAPIKey), "c")
    }

    func testDefaultURLHonoursEnvironmentVariable() {
        let url = SecretStore.defaultFileURL(environment: ["ASSISTANT_ENV_FILE": "/tmp/x/.env"])
        XCTAssertEqual(url.path, "/tmp/x/.env")
    }

    func testDefaultURLFallsBackToApplicationSupport() {
        let url = SecretStore.defaultFileURL(environment: [:])
        XCTAssertTrue(url.path.hasSuffix("Application Support/Assistant/.env"), url.path)
    }
    // MARK: - Interprocess locking

    func testConcurrentWritersFromTwoStoresLoseNoKeys() throws {
        let a = SecretStore(fileURL: envURL)
        let b = SecretStore(fileURL: envURL)
        let keys = SecretKey.allCases
        let rounds = 20
        DispatchQueue.concurrentPerform(iterations: keys.count * rounds) { i in
            let key = keys[i % keys.count]
            let store = i % 2 == 0 ? a : b
            do { try store.set(key, value: "v-\(key.rawValue)-\(i / keys.count)") } catch { XCTFail("\(error)") }
        }
        for key in keys {
            let value = try XCTUnwrap(try SecretStore(fileURL: envURL).get(key), "lost \(key)")
            XCTAssertTrue(value.hasPrefix("v-\(key.rawValue)-"))
        }
    }

    func testLockFileIsOwnerOnlySidecarOfResolvedPath() throws {
        let real = dir.appendingPathComponent("shared.env")
        try FileManager.default.createSymbolicLink(at: envURL, withDestinationURL: real)
        try SecretStore(fileURL: envURL).set(.claudeAPIKey, value: "x")
        let lock = SecretStore.lockFileURL(for: envURL)
        XCTAssertEqual(lock.path, real.path + ".lock")
        let perms = try FileManager.default.attributesOfItem(atPath: lock.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    /// flock() locks belong to an open file description, so a lock taken on a
    /// separate descriptor stands in for another process (e.g. the migration
    /// script) holding the lock.
    func testWriteWaitsForLockHeldElsewhere() throws {
        let store = SecretStore(fileURL: envURL)
        try store.set(.openaiAPIKey, value: "first")
        let lockPath = SecretStore.lockFileURL(for: envURL).path
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(flock(fd, LOCK_EX), 0)

        let done = expectation(description: "write finished")
        DispatchQueue.global().async {
            do { try store.set(.claudeAPIKey, value: "second") } catch { XCTFail("\(error)") }
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertNil(try store.get(.claudeAPIKey), "write must block while another holder has the lock")
        flock(fd, LOCK_UN)
        close(fd)
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try store.get(.claudeAPIKey), "second")
        XCTAssertEqual(try store.get(.openaiAPIKey), "first")
    }
}
