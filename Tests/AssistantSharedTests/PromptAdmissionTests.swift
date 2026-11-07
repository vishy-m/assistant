import XCTest
@testable import AssistantShared

final class PromptAdmissionTests: XCTestCase {

    func testPreflightRejectsOversizedBodies() {
        XCTAssertTrue(PromptAdmission.preflight(byteCount: 1_000))
        XCTAssertTrue(PromptAdmission.preflight(byteCount: 14 * 1024 * 1024))
        XCTAssertFalse(PromptAdmission.preflight(byteCount: 14 * 1024 * 1024 + 1))
    }

    func testFieldCaps() {
        XCTAssertNil(PromptAdmission.fieldError(textBytes: 10, imageBytes: 0,
                                                sessionIdBytes: 36, mediaTypeBytes: 9))
        XCTAssertNotNil(PromptAdmission.fieldError(textBytes: 100_001, imageBytes: 0,
                                                   sessionIdBytes: 0, mediaTypeBytes: 0))
        XCTAssertNotNil(PromptAdmission.fieldError(textBytes: 0, imageBytes: 10 * 1024 * 1024 + 1,
                                                   sessionIdBytes: 0, mediaTypeBytes: 0))
        XCTAssertNotNil(PromptAdmission.fieldError(textBytes: 5, imageBytes: 0,
                                                   sessionIdBytes: 129, mediaTypeBytes: 0))
        XCTAssertNotNil(PromptAdmission.fieldError(textBytes: 5, imageBytes: 0,
                                                   sessionIdBytes: 0, mediaTypeBytes: 129))
    }

    func testSmallRequestDecodesAndPasses() throws {
        let data = try JSONEncoder().encode(PromptRequest(text: "hi", sessionId: "abc"))
        XCTAssertTrue(PromptAdmission.preflight(byteCount: data.count))
        let req = try JSONDecoder().decode(PromptRequest.self, from: data)
        XCTAssertNil(PromptAdmission.fieldError(for: req))
        let long = PromptRequest(text: "hi", sessionId: String(repeating: "s", count: 129))
        XCTAssertNotNil(PromptAdmission.fieldError(for: long))
    }

    func testInFlightGateCapsConcurrentPrompts() {
        let gate = PromptAdmission.InFlightGate(limit: 2)
        XCTAssertTrue(gate.tryEnter())
        XCTAssertTrue(gate.tryEnter())
        XCTAssertFalse(gate.tryEnter())
        gate.leave()
        XCTAssertTrue(gate.tryEnter())
        gate.leave(); gate.leave(); gate.leave()   // extra leave never goes negative
        XCTAssertTrue(gate.tryEnter())
        XCTAssertTrue(gate.tryEnter())
        XCTAssertFalse(gate.tryEnter())
    }

    // MARK: - XPCPayloadLimit (NEW-2)

    func testJSONCap() {
        XCTAssertTrue(XPCPayloadLimit.allowsJSON(Data(count: 256 * 1024)))
        XCTAssertFalse(XPCPayloadLimit.allowsJSON(Data(count: 256 * 1024 + 1)))
    }

    func testFileCapUsesByteCount() {
        XCTAssertTrue(XPCPayloadLimit.allowsFileBytes(64 * 1024 * 1024))
        XCTAssertFalse(XPCPayloadLimit.allowsFileBytes(64 * 1024 * 1024 + 1))
    }

    func testShortStringCap() {
        XCTAssertTrue(XPCPayloadLimit.allowsShortString(String(repeating: "a", count: 8 * 1024)))
        XCTAssertFalse(XPCPayloadLimit.allowsShortString(String(repeating: "a", count: 8 * 1024 + 1)))
        // Counted in UTF-8 bytes, not characters.
        XCTAssertFalse(XPCPayloadLimit.allowsShortString(String(repeating: "é", count: 4 * 1024 + 1)))
    }

    func testTasksNoteCapCountsUTF8Bytes() {
        let limit = XPCPayloadLimit.maxTasksNoteBytes
        XCTAssertEqual(limit, 64 * 1024)
        XCTAssertTrue(XPCPayloadLimit.allowsTasksNote(String(repeating: "a", count: limit)))
        XCTAssertFalse(XPCPayloadLimit.allowsTasksNote(String(repeating: "a", count: limit + 1)))
        // "é" is 2 UTF-8 bytes. Exactly at the limit is allowed.
        let exact = String(repeating: "é", count: limit / 2)
        XCTAssertEqual(exact.utf8.count, limit)
        XCTAssertTrue(XPCPayloadLimit.allowsTasksNote(exact))
        // Character count is under the cap; byte count is two over.
        let over = String(repeating: "é", count: limit / 2 + 1)
        XCTAssertLessThan(over.count, limit)
        XCTAssertEqual(over.utf8.count, limit + 2)
        XCTAssertFalse(XPCPayloadLimit.allowsTasksNote(over))
    }
}
