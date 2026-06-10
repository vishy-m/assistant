import XCTest
@testable import AssistantLLM

final class MockHTTPClientTests: XCTestCase {

    func testReturnsQueuedResponse() async throws {
        let client = MockHTTPClient()
        let body = #"{"ok":true}"#.data(using: .utf8)!
        client.enqueue(.success((data: body, statusCode: 200)))

        var req = URLRequest(url: URL(string: "https://example.com/x")!)
        req.httpMethod = "POST"
        let result = try await client.send(req)

        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.data, body)
    }

    func testThrowsWhenQueueExhausted() async {
        let client = MockHTTPClient()
        do {
            _ = try await client.send(URLRequest(url: URL(string: "https://x")!))
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }

    func testThrowsWhenQueuedError() async {
        let client = MockHTTPClient()
        client.enqueue(.failure(URLError(.networkConnectionLost)))
        do {
            _ = try await client.send(URLRequest(url: URL(string: "https://x")!))
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }

    func testCapturesSentRequests() async throws {
        let client = MockHTTPClient()
        client.enqueue(.success((Data(), 200)))
        client.enqueue(.success((Data(), 200)))

        var r1 = URLRequest(url: URL(string: "https://a")!); r1.httpMethod = "POST"
        var r2 = URLRequest(url: URL(string: "https://b")!); r2.httpMethod = "GET"
        _ = try await client.send(r1)
        _ = try await client.send(r2)

        XCTAssertEqual(client.sentRequests.count, 2)
        XCTAssertEqual(client.sentRequests[1].url?.absoluteString, "https://b")
    }
}
