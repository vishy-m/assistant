import Foundation

public struct PromptResponse: Codable, Equatable {
    public let text: String
    public let modelUsed: String
    public let needsFollowup: Bool
    public let sessionId: String?
    public let errorMessage: String?

    public init(text: String, modelUsed: String, needsFollowup: Bool,
                sessionId: String?, errorMessage: String?) {
        self.text = text
        self.modelUsed = modelUsed
        self.needsFollowup = needsFollowup
        self.sessionId = sessionId
        self.errorMessage = errorMessage
    }
}
