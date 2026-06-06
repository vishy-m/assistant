import GRDB

enum Migration012EventClassLink {
    static let identifier = "012_event_class_link"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            // gcal_event_cache is a sync cache rebuilt from Google (the source of
            // truth lives in each event's extended properties), so these are bare
            // nullable references — no FK/cascade. Sync upserts events in arbitrary
            // order, so a referenced course/event_type row may not exist yet, and a
            // deleted course should not cascade-delete cached events. This mirrors
            // the existing `category` and `recurring_event_id` columns.
            try db.execute(sql: "ALTER TABLE gcal_event_cache ADD COLUMN course_id TEXT")
            try db.execute(sql: "ALTER TABLE gcal_event_cache ADD COLUMN event_type TEXT")
        }
    }
}
