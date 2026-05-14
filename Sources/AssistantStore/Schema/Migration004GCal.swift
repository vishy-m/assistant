import GRDB

enum Migration004GCal {
    static let identifier = "004_gcal"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE gcal_event_cache (
                    gcal_event_id  TEXT PRIMARY KEY NOT NULL,
                    calendar_id    TEXT NOT NULL,
                    title          TEXT NOT NULL,
                    start_at       TEXT NOT NULL,
                    end_at         TEXT NOT NULL,
                    location       TEXT,
                    category       TEXT NOT NULL DEFAULT 'generic',
                    last_synced_at TEXT NOT NULL,
                    raw_json       TEXT NOT NULL
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_gcal_cache_start ON gcal_event_cache(start_at)")
            try db.execute(sql: "CREATE INDEX idx_gcal_cache_calendar ON gcal_event_cache(calendar_id)")

            try db.execute(sql: """
                CREATE TABLE pending_gcal_op (
                    id              TEXT PRIMARY KEY NOT NULL,
                    op_type         TEXT NOT NULL,
                    payload_json    TEXT NOT NULL,
                    attempts        INTEGER NOT NULL DEFAULT 0,
                    last_attempt_at TEXT,
                    created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_pending_gcal_created ON pending_gcal_op(created_at)")
        }
    }
}
