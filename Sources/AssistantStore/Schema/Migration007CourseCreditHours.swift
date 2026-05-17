import GRDB

enum Migration007CourseCreditHours {
    static let identifier = "007_course_credit_hours"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: "ALTER TABLE course ADD COLUMN credit_hours REAL")
        }
    }
}
