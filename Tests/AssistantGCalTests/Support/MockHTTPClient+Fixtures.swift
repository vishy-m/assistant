import Foundation
@testable import AssistantLLM

extension MockHTTPClient {
    func enqueueJSON(_ json: String, status: Int = 200) {
        enqueue(.success((data: json.data(using: .utf8)!, statusCode: status)))
    }
}
