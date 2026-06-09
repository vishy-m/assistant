import XCTest
@testable import AssistantStore

final class ConversationRepositoryTests: XCTestCase {

    func testStartAndAppend() throws {
        let db = try InMemoryDB.make()
        let repo = ConversationRepository(db: db)

        let convo = try repo.start(id: "c1")
        try repo.appendMessage(Message(
            id: "m1", conversationId: convo.id, role: "user",
            content: "hi", attachedImagePath: nil, toolCallsJson: nil,
            modelUsed: nil, createdAt: Date()))
        try repo.appendMessage(Message(
            id: "m2", conversationId: convo.id, role: "assistant",
            content: "hello", attachedImagePath: nil, toolCallsJson: nil,
            modelUsed: "claude-sonnet-4-6", createdAt: Date()))

        XCTAssertEqual(try repo.messages(in: convo.id).count, 2)
    }

    func testCascadeDeleteMessages() throws {
        let db = try InMemoryDB.make()
        let repo = ConversationRepository(db: db)
        let convo = try repo.start(id: "c1")
        try repo.appendMessage(Message(
            id: "m1", conversationId: convo.id, role: "user",
            content: "hi", attachedImagePath: nil, toolCallsJson: nil,
            modelUsed: nil, createdAt: Date()))
        try repo.delete(id: convo.id)
        XCTAssertEqual(try repo.messages(in: convo.id).count, 0)
    }
}
