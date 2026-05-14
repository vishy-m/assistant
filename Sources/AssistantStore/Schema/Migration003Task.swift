import GRDB

enum Migration003Task {
    static let identifier = "003_task"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE TABLE task (
                    id             TEXT PRIMARY KEY NOT NULL,
                    title          TEXT NOT NULL,
                    notes          TEXT,
                    due_at         TEXT,
                    completed_at   TEXT,
                    course_id      TEXT REFERENCES course(id) ON DELETE SET NULL,
                    grade_item_id  TEXT REFERENCES grade_item(id) ON DELETE SET NULL,
                    priority       INTEGER NOT NULL DEFAULT 0,
                    category       TEXT NOT NULL DEFAULT 'generic',
                    source         TEXT NOT NULL DEFAULT 'manual',
                    created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
            """)
            try db.execute(sql: "CREATE INDEX idx_task_due_at ON task(due_at) WHERE completed_at IS NULL")
            try db.execute(sql: "CREATE INDEX idx_task_course ON task(course_id)")
        }
    }
}
