import Foundation

@objc(AssistantServiceProtocol)
public protocol AssistantServiceProtocol {
    func ping(reply: @escaping (String) -> Void)
    func getTodayPlan(reply: @escaping (Data) -> Void)
    func submitPrompt(_ requestData: Data, reply: @escaping (Data) -> Void)
    func setGoogleRefreshToken(_ token: String, reply: @escaping (Bool) -> Void)
    func getMostRecentSessionId(reply: @escaping (String?) -> Void)
    func getMessages(sessionId: String, reply: @escaping (Data) -> Void)
}
