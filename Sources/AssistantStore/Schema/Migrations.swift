import Foundation
import GRDB

/// Central registry of schema migrations. Add new migrations by appending here.
/// Never edit a migration after it ships to a user — write a new one instead.
public enum Migrations {

    public static func register(_ migrator: inout DatabaseMigrator) {
        // Migrations registered in order; each task in this plan adds one.
        // (Tasks 3–8 populate this list.)
    }
}
