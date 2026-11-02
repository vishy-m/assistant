import GRDB

/// Google event ids are unique per calendar only, so the cache key becomes
/// `(calendar_id, gcal_event_id)`. SQLite cannot change a primary key in place,
/// so the table is rebuilt and every existing row is copied over unchanged.
///
/// Numbered 016 because 014/015 are taken on the syllabus branch. GRDB tracks
/// applied migrations by identifier, so this runs correctly whether or not
/// 014/015 are present or applied.
enum Migration016GCalIdentity {
    static let identifier = "016_gcal_identity"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try migrate(db)
        }
    }

    /// Safe to run more than once: it returns early when the key is already composite.
    static func migrate(_ db: Database) throws {
        if try db.primaryKey("gcal_event_cache").columns == ["calendar_id", "gcal_event_id"] {
            return
        }
        let columns = """
            gcal_event_id, calendar_id, title, start_at, end_at, location, category,
            last_synced_at, raw_json, recurring_event_id, course_id, event_type
            """
        try db.execute(sql: "DROP TABLE IF EXISTS gcal_event_cache_new")
        try db.execute(sql: """
            CREATE TABLE gcal_event_cache_new (
                gcal_event_id      TEXT NOT NULL,
                calendar_id        TEXT NOT NULL,
                title              TEXT NOT NULL,
                start_at           TEXT NOT NULL,
                end_at             TEXT NOT NULL,
                location           TEXT,
                category           TEXT NOT NULL DEFAULT 'Misc',
                last_synced_at     TEXT NOT NULL,
                raw_json           TEXT NOT NULL,
                recurring_event_id TEXT,
                course_id          TEXT,
                event_type         TEXT,
                PRIMARY KEY (calendar_id, gcal_event_id)
            ) STRICT
            """)
        // The old key was gcal_event_id alone, so no two rows can collide here.
        try db.execute(sql: """
            INSERT INTO gcal_event_cache_new (\(columns))
            SELECT \(columns) FROM gcal_event_cache
            """)
        try db.execute(sql: "DROP TABLE gcal_event_cache")
        try db.execute(sql: "ALTER TABLE gcal_event_cache_new RENAME TO gcal_event_cache")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_gcal_cache_start ON gcal_event_cache(start_at)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_gcal_cache_calendar ON gcal_event_cache(calendar_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_gcal_cache_event_id ON gcal_event_cache(gcal_event_id)")
    }
}
