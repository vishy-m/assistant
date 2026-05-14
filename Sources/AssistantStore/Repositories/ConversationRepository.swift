import Foundation
import GRDB

public struct ConversationRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func start(id: String) throws -> Conversation {
        let c = Conversation(id: id)
        try db.queue.write { db in try c.insert(db) }
        return c
    }

    public func find(id: String) throws -> Conversation? {
        try db.queue.read { db in try Conversation.fetchOne(db, key: id) }
    }

    public func appendMessage(_ m: Message) throws {
        try db.queue.write { db in
            try m.insert(db)
            try db.execute(sql: """
                UPDATE conversation SET last_active_at = ? WHERE id = ?
            """, arguments: [m.createdAt, m.conversationId])
        }
    }

    public func messages(in convoId: String) throws -> [Message] {
        try db.queue.read { db in
            try Message
                .filter(Column("conversation_id") == convoId)
                .order(Column("created_at"))
                .fetchAll(db)
        }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { db in
            try Conversation.deleteOne(db, key: id)
        }
    }

    public func mostRecent(limit: Int = 20) throws -> [Conversation] {
        try db.queue.read { db in
            try Conversation
                .order(Column("last_active_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
