import GRDB

enum Migration008Category {
    static let identifier = "008_category"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE category (
                    name       TEXT PRIMARY KEY NOT NULL,
                    color_hex  TEXT NOT NULL,
                    is_default INTEGER NOT NULL DEFAULT 0
                ) STRICT
            """)

            let seed: [(String, String, Int)] = [
                ("Misc",       "8A8F98", 1),
                ("Class",      "4F6B7A", 0),
                ("Exam",       "7A5C5C", 0),
                ("Assignment", "7A6F4F", 0),
                ("Club",       "4F7561", 0),
                ("Personal",   "6B5C7A", 0)
            ]
            for (name, hex, def) in seed {
                try db.execute(
                    sql: "INSERT INTO category (name, color_hex, is_default) VALUES (?, ?, ?)",
                    arguments: [name, hex, def])
            }

            try db.execute(sql: "UPDATE gcal_event_cache SET category = 'Misc' WHERE category = 'generic'")
            try db.execute(sql: "UPDATE task SET category = 'Misc' WHERE category = 'generic'")
        }
    }
}
