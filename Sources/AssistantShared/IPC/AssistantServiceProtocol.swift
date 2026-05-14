import Foundation

@objc(AssistantServiceProtocol)
public protocol AssistantServiceProtocol {
    func ping(reply: @escaping (String) -> Void)
}
