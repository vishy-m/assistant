import GRDB

enum Migration009RecurringEventId {
    static let identifier = "009_recurring_event_id"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: "ALTER TABLE gcal_event_cache ADD COLUMN recurring_event_id TEXT")
        }
    }
}
