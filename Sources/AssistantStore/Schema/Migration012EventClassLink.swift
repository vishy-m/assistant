import GRDB

enum Migration012EventClassLink {
    static let identifier = "012_event_class_link"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: "ALTER TABLE gcal_event_cache ADD COLUMN course_id TEXT")
            try db.execute(sql: "ALTER TABLE gcal_event_cache ADD COLUMN event_type TEXT")
        }
    }
}
