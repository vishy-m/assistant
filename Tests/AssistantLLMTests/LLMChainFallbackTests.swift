import XCTest
@testable import AssistantLLM

final class LLMChainFallbackTests: XCTestCase {

    // A test double that succeeds, fails, or throws on demand.
    private final class StubProvider: LLMProvider, @unchecked Sendable {
        let name: String
        var configured: Bool
        var outcome: Result<LLMResponse, Error>
        var callCount = 0
        init(name: String, configured: Bool = true, outcome: Result<LLMResponse, Error>) {
            self.name = name
            self.configured = configured
            self.outcome = outcome
        }
        func isConfigured() -> Bool { configured }
        func complete(messages: [LLMMessage], tools: [LLMTool]) async throws -> LLMResponse {
            callCount += 1
            return try outcome.get()
        }
    }

    private func okResp(_ name: String) -> LLMResponse {
        LLMResponse(modelUsed: name, stopReason: .endTurn, content: [.text("from \(name)")])
    }

    func testFirstSucceedsNoFallthrough() async throws {
        let p1 = StubProvider(name: "p1", outcome: .success(okResp("p1")))
        let p2 = StubProvider(name: "p2", outcome: .success(okResp("p2")))
        let chain = LLMChain(providers: [p1, p2])

        let r = try await chain.complete(
            messages: [LLMMessage(role: .user, content: [.text("hi")])],
            tools: [])
        XCTAssertEqual(r.modelUsed, "p1")
        XCTAssertEqual(p2.callCount, 0)
    }

    func testRateLimitFallsThrough() async throws {
        let p1 = StubProvider(name: "p1", outcome: .failure(ProviderError.rateLimited))
        let p2 = StubProvider(name: "p2", outcome: .success(okResp("p2")))
        let chain = LLMChain(providers: [p1, p2])
        let r = try await chain.complete(
            messages: [LLMMessage(role: .user, content: [.text("x")])], tools: [])
        XCTAssertEqual(r.modelUsed, "p2")
    }

    func testNotConfiguredSkipsSilently() async throws {
        let p1 = StubProvider(name: "p1", configured: false, outcome: .failure(ProviderError.notConfigured))
        let p2 = StubProvider(name: "p2", outcome: .success(okResp("p2")))
        let chain = LLMChain(providers: [p1, p2])
        let r = try await chain.complete(
            messages: [LLMMessage(role: .user, content: [.text("x")])], tools: [])
        XCTAssertEqual(r.modelUsed, "p2")
        XCTAssertEqual(p1.callCount, 0) // skipped without invocation
    }

    func testClientErrorDoesNotFallThrough() async {
        let p1 = StubProvider(name: "p1",
                              outcome: .failure(ProviderError.clientError(statusCode: 400, message: "bad")))
        let p2 = StubProvider(name: "p2", outcome: .success(okResp("p2")))
        let chain = LLMChain(providers: [p1, p2])
        do {
            _ = try await chain.complete(
                messages: [LLMMessage(role: .user, content: [.text("x")])], tools: [])
            XCTFail("expected throw — 4xx errors are not retriable")
        } catch ChainError.allProvidersFailed {} catch { XCTFail("\(error)") }
    }

    func testAllProvidersFail() async {
        let p1 = StubProvider(name: "p1", outcome: .failure(ProviderError.rateLimited))
        let p2 = StubProvider(name: "p2", outcome: .failure(ProviderError.transient(message: "x")))
        let chain = LLMChain(providers: [p1, p2])
        do {
            _ = try await chain.complete(
                messages: [LLMMessage(role: .user, content: [.text("x")])], tools: [])
            XCTFail()
        } catch ChainError.allProvidersFailed(let errs) {
            XCTAssertEqual(errs.count, 2)
        } catch { XCTFail("\(error)") }
    }
}
