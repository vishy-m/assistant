import GRDB

enum Migration010CourseContact {
    static let identifier = "010_course_contact"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: "ALTER TABLE course ADD COLUMN professor_name TEXT")
            try db.execute(sql: "ALTER TABLE course ADD COLUMN professor_email TEXT")
            try db.execute(sql: "ALTER TABLE course ADD COLUMN classroom TEXT")
            try db.execute(sql: "ALTER TABLE course ADD COLUMN icon_name TEXT")
        }
    }
}
