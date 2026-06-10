import Foundation
import GRDB
@testable import AssistantStore

/// Builds an in-memory AssistantDB for tests. Avoids file I/O entirely.
enum InMemoryDB {
    static func make() throws -> AssistantDB {
        let queue = try DatabaseQueue()  // in-memory by default
        return try AssistantDB(queue: queue, runMigrationsOnInit: true)
    }
}
