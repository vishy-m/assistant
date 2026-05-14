import Foundation

public enum ChainPolicy {
    /// Returns true if the chain should try the next provider on this error.
    public static func shouldFallThrough(_ error: Error) -> Bool {
        guard let pe = error as? ProviderError else { return true }
        switch pe {
        case .notConfigured: return true
        case .rateLimited, .serverOverloaded: return true
        case .transient, .timeout: return true
        case .decodingFailure: return true        // try a different provider rather than fail
        case .clientError: return false           // 4xx — our fault, retry won't help
        }
    }
}
