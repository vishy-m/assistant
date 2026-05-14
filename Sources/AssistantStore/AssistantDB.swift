import Foundation
import GRDB

public final class AssistantDB {

    public let queue: DatabaseQueue

    /// Use for production — file-backed DB in app support dir.
    public convenience init(fileURL: URL) throws {
        let config = AssistantDB.makeConfiguration()
        let queue = try DatabaseQueue(path: fileURL.path, configuration: config)
        try self.init(queue: queue, runMigrationsOnInit: true)
    }

    /// Used by tests with in-memory queues.
    public init(queue: DatabaseQueue, runMigrationsOnInit: Bool) throws {
        self.queue = queue
        if runMigrationsOnInit {
            try runMigrations()
        }
    }

    public func runMigrations() throws {
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)
        try migrator.migrate(queue)
    }

    /// Default path: ~/Library/Application Support/Assistant/assistant.sqlite
    public static func defaultFileURL() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true)
        let dir = support.appendingPathComponent("Assistant", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("assistant.sqlite")
    }

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            // WAL is required by the spec and gives better concurrency.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return config
    }
}
