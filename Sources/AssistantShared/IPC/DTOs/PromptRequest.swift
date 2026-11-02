import Foundation

public struct PromptRequest: Codable, Equatable {
    public let text: String
    public let imageData: Data?
    public let imageMediaType: String?
    public let sessionId: String?
    public let attemptOpus: Bool

    public init(text: String, imageData: Data? = nil, imageMediaType: String? = nil,
                sessionId: String? = nil, attemptOpus: Bool = false) {
        self.text = text
        self.imageData = imageData
        self.imageMediaType = imageMediaType
        self.sessionId = sessionId
        self.attemptOpus = attemptOpus
    }
}

/// Admission checks for `submitPrompt`, split so the service can reject an
/// oversized body before decoding it and before spawning a task.
public enum PromptAdmission {
    public static let maxTextBytes = 100_000
    public static let maxImageBytes = 10 * 1024 * 1024
    public static let maxSessionIdBytes = 128
    public static let maxMediaTypeBytes = 128
    /// 10 MB image after base64 expansion, plus text and JSON overhead.
    public static let maxBodyBytes = 14 * 1024 * 1024
    /// Prompts decoding or running at once.
    public static let maxInFlight = 4

    /// Runs on the raw request size, before decoding.
    public static func preflight(byteCount: Int) -> Bool { byteCount <= maxBodyBytes }

    /// nil when every field is within its cap, else a reason.
    public static func fieldError(textBytes: Int, imageBytes: Int,
                                  sessionIdBytes: Int, mediaTypeBytes: Int) -> String? {
        if textBytes > maxTextBytes { return "text too large" }
        if imageBytes > maxImageBytes { return "image too large" }
        if sessionIdBytes > maxSessionIdBytes { return "session id too long" }
        if mediaTypeBytes > maxMediaTypeBytes { return "image media type too long" }
        return nil
    }

    public static func fieldError(for req: PromptRequest) -> String? {
        fieldError(textBytes: req.text.utf8.count,
                   imageBytes: req.imageData?.count ?? 0,
                   sessionIdBytes: req.sessionId?.utf8.count ?? 0,
                   mediaTypeBytes: req.imageMediaType?.utf8.count ?? 0)
    }

    /// Counting semaphore that refuses instead of blocking.
    public final class InFlightGate {
        private let lock = NSLock()
        private let limit: Int
        private var count = 0

        public init(limit: Int = PromptAdmission.maxInFlight) { self.limit = limit }

        public func tryEnter() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard count < limit else { return false }
            count += 1
            return true
        }

        public func leave() {
            lock.lock(); defer { lock.unlock() }
            if count > 0 { count -= 1 }
        }
    }
}
