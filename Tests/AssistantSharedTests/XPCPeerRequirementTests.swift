import XCTest
@testable import AssistantShared

final class XPCPeerRequirementTests: XCTestCase {

    func testTeamRequirementPinsAnchorAndTeam() {
        let result = XPCPeerRequirement.string(
            forIdentifier: "com.vishruth.assistant",
            team: "ABCDE12345",
            peerCDHash: nil)
        XCTAssertEqual(
            result,
            "anchor apple generic and identifier \"com.vishruth.assistant\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testMissingTeamAndCDHashReturnsNil() {
        XCTAssertNil(XPCPeerRequirement.string(
            forIdentifier: "com.vishruth.assistant",
            team: nil,
            peerCDHash: nil))
    }

    func testCDHashRequirementWhenTeamIsAbsent() {
        let result = XPCPeerRequirement.string(
            forIdentifier: "com.vishruth.assistant",
            team: nil,
            peerCDHash: "ab12")
        XCTAssertEqual(result, "identifier \"com.vishruth.assistant\" and cdhash H\"ab12\"")
    }

    func testQuotesInTeamAndIdentifierAreEscaped() {
        let result = XPCPeerRequirement.string(
            forIdentifier: "com.\"assistant",
            team: "AB\"CD",
            peerCDHash: nil)
        XCTAssertEqual(
            result,
            "anchor apple generic and identifier \"com.\\\"assistant\" and certificate leaf[subject.OU] = \"AB\\\"CD\""
        )
    }

    func testBackslashInTeamIsEscapedBeforeQuote() {
        let result = XPCPeerRequirement.string(
            forIdentifier: "com.vishruth.assistant",
            team: "A\\B\"C",
            peerCDHash: nil)
        XCTAssertEqual(
            result,
            "anchor apple generic and identifier \"com.vishruth.assistant\" and certificate leaf[subject.OU] = \"A\\\\B\\\"C\""
        )
    }

    func testEmptyTeamFallsThroughToCDHash() {
        let result = XPCPeerRequirement.string(
            forIdentifier: "com.vishruth.assistant",
            team: "",
            peerCDHash: "ab12")
        XCTAssertEqual(result, "identifier \"com.vishruth.assistant\" and cdhash H\"ab12\"")
    }

    func testUIBinaryOverrideWinsOverSibling() {
        let url = XPCPeerRequirement.resolvedUIBinaryURL(
            environment: ["ASSISTANT_UI_BINARY": "/tmp/Custom UI.app"],
            executableURL: URL(fileURLWithPath: "/tmp/Build/AssistantCoreHelper"))
        XCTAssertEqual(url?.path, "/tmp/Custom UI.app")
    }

    func testUIBinaryDefaultsToSiblingApp() {
        let url = XPCPeerRequirement.resolvedUIBinaryURL(
            environment: ["ASSISTANT_UI_BINARY": ""],
            executableURL: URL(fileURLWithPath: "/tmp/Build/AssistantCoreHelper"))
        XCTAssertEqual(url?.path, "/tmp/Build/AssistantUI.app")
    }

    func testAdHocBinaryCDHashIsLowercaseHex() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("w8-cdhash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let binary = dir.appendingPathComponent("helper")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: binary)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-s", "-", "-f", "-i", "com.vishruth.assistant", binary.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let hashes = XPCPeerRequirement.cdHashHexes(at: binary)
        XCTAssertFalse(hashes.isEmpty)
        for hash in hashes {
            XCTAssertTrue(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
            XCTAssertTrue(hash.count == 40 || hash.count == 64)
        }
        let requirement = XPCPeerRequirement.string(
            forIdentifier: "com.vishruth.assistant",
            team: nil,
            peerCDHash: hashes[0])
        XCTAssertEqual(requirement, "identifier \"com.vishruth.assistant\" and cdhash H\"\(hashes[0])\"")
    }
}
