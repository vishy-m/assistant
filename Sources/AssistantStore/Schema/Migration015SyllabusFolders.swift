import Foundation
import GRDB

/// Backfills a root-level "Syllabus" folder into every course that doesn't
/// already have one. Runs once — deleting the folder afterwards is permanent
/// (the scan feature simply stays off for that class).
enum Migration015SyllabusFolders {
    static let identifier = "015_syllabus_folders"

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            let courseIds = try String.fetchAll(db, sql: "SELECT id FROM course")
            for courseId in courseIds {
                let existing = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM class_folder
                    WHERE course_id = ? AND parent_folder_id IS NULL
                      AND LOWER(name) = 'syllabus'
                    """, arguments: [courseId]) ?? 0
                guard existing == 0 else { continue }
                try db.execute(sql: """
                    INSERT INTO class_folder
                        (id, course_id, parent_folder_id, name, sort_order,
                         created_at, updated_at)
                    VALUES (?, ?, NULL, 'Syllabus', 0, datetime('now'), datetime('now'))
                    """, arguments: [UUID().uuidString, courseId])
            }
        }
    }
}
