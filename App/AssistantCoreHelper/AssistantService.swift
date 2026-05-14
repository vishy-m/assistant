import Foundation
import AssistantShared

final class AssistantService: NSObject, AssistantServiceProtocol {
    func ping(reply: @escaping (String) -> Void) {
        reply("pong")
    }
}
