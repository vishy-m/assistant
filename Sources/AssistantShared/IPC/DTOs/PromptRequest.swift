import Foundation

public struct PromptRequest: Codable, Equatable {
    public let text: String
    public let imageData: Data?
    public let imageMediaType: String?
    public let sessionId: String?
    public let attemptOpus: Bool

    public init(text: String, imageData: Data? = nil, imageMediaType: String? = nil,
                sessionId: String? = nil, attemptOpus: Bool = false) {
        self.text = text
        self.imageData = imageData
        self.imageMediaType = imageMediaType
        self.sessionId = sessionId
        self.attemptOpus = attemptOpus
    }
}
