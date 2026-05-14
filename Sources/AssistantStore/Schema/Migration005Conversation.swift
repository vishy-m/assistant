import GRDB

enum Migration005Conversation {
    static let identifier = "005_conversation"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE conversation (
                    id              TEXT PRIMARY KEY NOT NULL,
                    started_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_active_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    summary         TEXT
                ) STRICT
            """)
            try db.execute(sql: """
                CREATE TABLE message (
                    id                  TEXT PRIMARY KEY NOT NULL,
                    conversation_id     TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
                    role                TEXT NOT NULL,
                    content             TEXT NOT NULL,
                    attached_image_path TEXT,
                    tool_calls_json     TEXT,
                    model_used          TEXT,
                    created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_message_conversation ON message(conversation_id, created_at)")
        }
    }
}
