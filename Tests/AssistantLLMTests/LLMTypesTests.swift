import XCTest
@testable import AssistantLLM

final class LLMTypesTests: XCTestCase {

    func testTextMessageRoundTrip() throws {
        let m = LLMMessage(role: .user, content: [.text("hello")])
        let encoded = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(LLMMessage.self, from: encoded)
        XCTAssertEqual(m, decoded)
    }

    func testImageMessageRoundTrip() throws {
        let data = Data([0xFF, 0xD8, 0xFF])
        let m = LLMMessage(role: .user, content: [
            .image(.init(mediaType: "image/jpeg", data: data)),
            .text("what is this?")
        ])
        let encoded = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(LLMMessage.self, from: encoded)
        XCTAssertEqual(m, decoded)
    }

    func testToolCallRoundTrip() throws {
        let tc = ToolCall(id: "call_1", name: "create_task",
                          argumentsJSON: #"{"title":"x"}"#)
        let data = try JSONEncoder().encode(tc)
        let back = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(tc, back)
    }
}
