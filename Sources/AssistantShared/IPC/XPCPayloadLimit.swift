import Foundation

/// Byte caps applied synchronously at XPC entry points, before any
/// `JSONDecoder` work or disk write. Callers reply with their method's
/// existing failure value when a check fails.
public enum XPCPayloadLimit {
    /// JSON-encoded DTO arguments.
    public static let maxJSONBytes = 256 * 1024
    /// Raw class-file bytes passed to `addClassFile`.
    public static let maxFileBytes = 64 * 1024 * 1024
    /// Short strings (names, ids, notes, secrets), counted in UTF-8 bytes.
    public static let maxShortStringBytes = 8 * 1024

    public static func allowsJSON(_ data: Data) -> Bool { data.count <= maxJSONBytes }
    public static func allowsFileBytes(_ count: Int) -> Bool { count <= maxFileBytes }
    public static func allowsShortString(_ s: String) -> Bool {
        s.utf8.count <= maxShortStringBytes
    }
}
