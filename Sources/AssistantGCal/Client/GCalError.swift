import Foundation

public enum GCalError: Error, Equatable {
    case unauthorized           // 401
    case forbidden              // 403
    case notFound               // 404
    case conflict               // 409 (e.g. a client-supplied event id already exists)
    case rateLimited            // 429
    case server(Int)            // 5xx
    case syncTokenInvalid       // 410 with reason=fullSyncRequired
    case network(String)
    case decoding(String)
    case quotaExceededLocally
}
