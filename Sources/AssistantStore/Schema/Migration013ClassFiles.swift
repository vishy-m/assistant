import GRDB

enum Migration013ClassFiles {
    static let identifier = "013_class_files"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE class_folder (
                    id               TEXT PRIMARY KEY NOT NULL,
                    course_id        TEXT NOT NULL,
                    parent_folder_id TEXT,
                    name             TEXT NOT NULL,
                    sort_order       INTEGER NOT NULL DEFAULT 0,
                    created_at       TEXT NOT NULL,
                    updated_at       TEXT NOT NULL
                ) STRICT
            """)
            try db.execute(sql: """
                CREATE TABLE class_file (
                    id           TEXT PRIMARY KEY NOT NULL,
                    course_id    TEXT NOT NULL,
                    folder_id    TEXT,
                    name         TEXT NOT NULL,
                    stored_name  TEXT NOT NULL,
                    content_type TEXT NOT NULL,
                    byte_size    INTEGER NOT NULL,
                    created_at   TEXT NOT NULL,
                    updated_at   TEXT NOT NULL
                ) STRICT
            """)
            try db.execute(sql: """
                CREATE TABLE class_pin (
                    id         TEXT PRIMARY KEY NOT NULL,
                    course_id  TEXT NOT NULL,
                    file_id    TEXT NOT NULL,
                    x          REAL NOT NULL,
                    y          REAL NOT NULL,
                    width      REAL NOT NULL,
                    height     REAL NOT NULL,
                    rotation   REAL NOT NULL DEFAULT 0,
                    z_order    INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_class_folder_course ON class_folder(course_id)")
            try db.execute(sql: "CREATE INDEX idx_class_file_course ON class_file(course_id)")
            try db.execute(sql: "CREATE INDEX idx_class_pin_course ON class_pin(course_id)")
        }
    }
}
