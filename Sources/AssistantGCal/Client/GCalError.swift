import Foundation

public enum GCalError: Error, Equatable {
    case unauthorized           // 401
    case forbidden              // 403
    case notFound               // 404
    case rateLimited            // 429
    case server(Int)            // 5xx
    case syncTokenInvalid       // 410 with reason=fullSyncRequired
    case network(String)
    case decoding(String)
    case quotaExceededLocally
}
