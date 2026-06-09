import Foundation
import GRDB
@testable import AssistantStore

enum InMemoryDB {
    static func make() throws -> AssistantDB {
        let queue = try DatabaseQueue()
        return try AssistantDB(queue: queue, runMigrationsOnInit: true)
    }
}
