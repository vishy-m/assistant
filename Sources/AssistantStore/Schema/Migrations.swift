import Foundation
import GRDB

/// Central registry of schema migrations. Add new migrations by appending here.
/// Never edit a migration after it ships to a user — write a new one instead.
public enum Migrations {

    public static func register(_ migrator: inout DatabaseMigrator) {
        Migration001Setting.register(&migrator)
        Migration002Course.register(&migrator)
        Migration003Task.register(&migrator)
        Migration004GCal.register(&migrator)
        Migration005Conversation.register(&migrator)
        Migration006Briefing.register(&migrator)
        Migration007CourseCreditHours.register(&migrator)
        Migration008Category.register(&migrator)
        Migration009RecurringEventId.register(&migrator)
        Migration010CourseContact.register(&migrator)
    }
}
