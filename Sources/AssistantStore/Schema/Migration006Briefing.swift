import GRDB

enum Migration006Briefing {
    static let identifier = "006_briefing"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE briefing_log (
                    id            TEXT PRIMARY KEY NOT NULL,
                    kind          TEXT NOT NULL,
                    fired_at      TEXT NOT NULL,
                    payload_json  TEXT NOT NULL,
                    dismissed_at  TEXT,
                    acted_on      INTEGER NOT NULL DEFAULT 0
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_briefing_fired ON briefing_log(fired_at)")
        }
    }
}
