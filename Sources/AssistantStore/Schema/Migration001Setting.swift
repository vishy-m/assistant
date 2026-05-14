import GRDB

enum Migration001Setting {
    static let identifier = "001_setting"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE setting (
                    key         TEXT PRIMARY KEY NOT NULL,
                    value_json  BLOB NOT NULL,
                    updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
            """)
        }
    }
}
