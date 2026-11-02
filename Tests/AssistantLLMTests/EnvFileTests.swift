import XCTest
@testable import AssistantLLM

final class EnvFileTests: XCTestCase {

    func testParsesBareQuotedAndExportedValues() {
        let env = EnvFile(contents: """
        # comment
        A=plain
        export B=exported
        C="double quoted # not a comment"
        D='single quoted'
        E=value # trailing comment
          F = spaced
        G="esc\\"aped\\\\slash\\nnewline"
        """)
        XCTAssertEqual(env.value(for: "A"), "plain")
        XCTAssertEqual(env.value(for: "B"), "exported")
        XCTAssertEqual(env.value(for: "C"), "double quoted # not a comment")
        XCTAssertEqual(env.value(for: "D"), "single quoted")
        XCTAssertEqual(env.value(for: "E"), "value")
        XCTAssertEqual(env.value(for: "F"), "spaced")
        XCTAssertEqual(env.value(for: "G"), "esc\"aped\\slash\nnewline")
    }

    func testValueContainingEqualsKeepsEverythingAfterFirstEquals() {
        let env = EnvFile(contents: "TOKEN=abc==\n")
        XCTAssertEqual(env.value(for: "TOKEN"), "abc==")
    }

    func testMissingKeyIsNil() {
        XCTAssertNil(EnvFile(contents: "A=1").value(for: "B"))
    }

    func testLastDuplicateWins() {
        XCTAssertEqual(EnvFile(contents: "A=1\nA=2\n").value(for: "A"), "2")
    }

    func testSetReplacesInPlaceAndPreservesOtherLines() {
        var env = EnvFile(contents: "# keys\nA=1\n\nB=2\n")
        env.set("A", value: "new")
        XCTAssertEqual(env.serialized(), "# keys\nA=new\n\nB=2\n")
    }

    func testSetCollapsesDuplicates() {
        var env = EnvFile(contents: "A=1\nB=x\nA=2\n")
        env.set("A", value: "3")
        XCTAssertEqual(env.serialized(), "A=3\nB=x\n")
    }

    func testSetAppendsNewKey() {
        var env = EnvFile(contents: "A=1")
        env.set("B", value: "2")
        XCTAssertEqual(env.serialized(), "A=1\nB=2\n")
    }

    func testRemoveDropsAllOccurrences() {
        var env = EnvFile(contents: "A=1\nB=2\nA=3\n")
        env.remove("A")
        XCTAssertEqual(env.serialized(), "B=2\n")
    }

    func testValuesWithSpecialCharactersRoundTrip() {
        let tricky = "has space # and \"quotes\" \\ and\nnewline"
        var env = EnvFile(contents: "")
        env.set("K", value: tricky)
        XCTAssertEqual(EnvFile(contents: env.serialized()).value(for: "K"), tricky)
    }

    func testTypicalSecretsAreWrittenBare() {
        var env = EnvFile(contents: "")
        env.set("ANTHROPIC_API_KEY", value: "sk-ant-api03-AbC_d-123")
        env.set("GOOGLE_OAUTH_REFRESH_TOKEN", value: "1//0gAbC-d_E")
        XCTAssertEqual(env.serialized(),
                       "ANTHROPIC_API_KEY=sk-ant-api03-AbC_d-123\nGOOGLE_OAUTH_REFRESH_TOKEN=1//0gAbC-d_E\n")
    }
}
