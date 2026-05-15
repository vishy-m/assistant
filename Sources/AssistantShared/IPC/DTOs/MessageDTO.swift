import Foundation

public struct MessageDTO: Codable, Equatable {
    public let id: String
    public let role: String
    public let content: String
    public let modelUsed: String?
    public let createdAt: Date

    public init(id: String, role: String, content: String, modelUsed: String?, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}
