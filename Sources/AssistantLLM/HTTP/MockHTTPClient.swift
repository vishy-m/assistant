import Foundation

public final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    public typealias Outcome = Result<(data: Data, statusCode: Int), Error>

    private let lock = NSLock()
    private var queue: [Outcome] = []
    public private(set) var sentRequests: [URLRequest] = []

    public init() {}

    public func enqueue(_ outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        queue.append(outcome)
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.lock()
        sentRequests.append(request)
        guard !queue.isEmpty else {
            lock.unlock()
            throw MockHTTPClientError.queueExhausted
        }
        let next = queue.removeFirst()
        lock.unlock()
        switch next {
        case .success(let (data, status)): return HTTPResponse(data: data, statusCode: status)
        case .failure(let error): throw error
        }
    }
}

public enum MockHTTPClientError: Error { case queueExhausted }
