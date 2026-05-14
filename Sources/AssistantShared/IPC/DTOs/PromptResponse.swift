import Foundation

public struct PromptResponse: Codable, Equatable {
    public let text: String
    public let modelUsed: String
    public let needsFollowup: Bool
    public let errorMessage: String?

    public init(text: String, modelUsed: String, needsFollowup: Bool, errorMessage: String?) {
        self.text = text
        self.modelUsed = modelUsed
        self.needsFollowup = needsFollowup
        self.errorMessage = errorMessage
    }
}
