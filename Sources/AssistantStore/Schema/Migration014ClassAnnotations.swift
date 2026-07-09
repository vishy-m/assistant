import GRDB

enum Migration014ClassAnnotations {
    static let identifier = "014_class_annotations"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE class_annotation (
                    id         TEXT PRIMARY KEY NOT NULL,
                    course_id  TEXT NOT NULL,
                    kind       TEXT NOT NULL,
                    x          REAL NOT NULL,
                    y          REAL NOT NULL,
                    width      REAL NOT NULL,
                    height     REAL NOT NULL,
                    z_order    INTEGER NOT NULL DEFAULT 0,
                    payload    TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_class_annotation_course ON class_annotation(course_id)")
        }
    }
}
