import GRDB

enum Migration002Course {
    static let identifier = "002_course"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE course (
                    id                   TEXT PRIMARY KEY NOT NULL,
                    name                 TEXT NOT NULL,
                    term                 TEXT,
                    color                TEXT,
                    target_grade         TEXT,
                    grading_scale_json   TEXT,
                    syllabus_source_path TEXT,
                    created_at           TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at           TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
            """)

            try db.execute(sql: """
                CREATE TABLE grade_category (
                    id              TEXT PRIMARY KEY NOT NULL,
                    course_id       TEXT NOT NULL REFERENCES course(id) ON DELETE CASCADE,
                    name            TEXT NOT NULL,
                    weight_pct      REAL NOT NULL,
                    drop_lowest_n   INTEGER NOT NULL DEFAULT 0,
                    drop_highest_n  INTEGER NOT NULL DEFAULT 0
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_grade_category_course ON grade_category(course_id)")

            try db.execute(sql: """
                CREATE TABLE grade_item (
                    id                   TEXT PRIMARY KEY NOT NULL,
                    course_id            TEXT NOT NULL REFERENCES course(id) ON DELETE CASCADE,
                    category_id          TEXT REFERENCES grade_category(id) ON DELETE SET NULL,
                    name                 TEXT NOT NULL,
                    max_points           REAL NOT NULL,
                    earned_points        REAL,
                    due_at               TEXT,
                    is_extra_credit      INTEGER NOT NULL DEFAULT 0,
                    weight_override_pct  REAL,
                    created_at           TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at           TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_grade_item_course ON grade_item(course_id)")
            try db.execute(sql: "CREATE INDEX idx_grade_item_category ON grade_item(category_id)")
        }
    }
}
