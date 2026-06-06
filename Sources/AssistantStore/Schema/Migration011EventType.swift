import GRDB

enum Migration011EventType {
    static let identifier = "011_event_type"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE event_type (
                    id              TEXT PRIMARY KEY NOT NULL,
                    name            TEXT NOT NULL,
                    color_hex       TEXT NOT NULL,
                    google_color_id TEXT NOT NULL,
                    symbol_name     TEXT,
                    is_builtin      INTEGER NOT NULL DEFAULT 0,
                    sort_order      INTEGER NOT NULL DEFAULT 0
                ) STRICT
            """)

            // (id, name, color_hex, google_color_id, symbol_name, sort_order)
            let seed: [(String, String, String, String, String, Int)] = [
                ("class",        "Class",            "7986CB", "1",  "book.closed",                  0),
                ("office_hours", "Office Hours",     "33B679", "2",  "person.fill.questionmark",     1),
                ("discussion",   "Discussion",       "8E24AA", "3",  "bubble.left.and.bubble.right", 2),
                ("exam",         "Midterm / Final",  "D50000", "11", "doc.text.magnifyingglass",     3)
            ]
            for (id, name, hex, gcid, symbol, order) in seed {
                try db.execute(sql: """
                    INSERT INTO event_type
                        (id, name, color_hex, google_color_id, symbol_name, is_builtin, sort_order)
                    VALUES (?, ?, ?, ?, ?, 1, ?)
                    """, arguments: [id, name, hex, gcid, symbol, order])
            }
        }
    }
}
