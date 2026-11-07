import Foundation

/// Byte caps applied synchronously at XPC entry points, before any
/// `JSONDecoder` work or disk write. Callers reply with their method's
/// existing failure value when a check fails.
public enum XPCPayloadLimit {
    /// JSON-encoded DTO arguments.
    public static let maxJSONBytes = 256 * 1024
    /// Raw class-file bytes passed to `addClassFile`.
    public static let maxFileBytes = 64 * 1024 * 1024
    /// Short strings (names, ids, secrets), counted in UTF-8 bytes.
    /// The tasks scratchpad uses `maxTasksNoteBytes` instead.
    public static let maxShortStringBytes = 8 * 1024
    /// `setTasksNote` scratchpad. A note can be a few pages, so it is larger
    /// than a name or a Google token, but still bounded: 64 KiB is enough for
    /// a long plain-text note and stays well under `maxJSONBytes`, so one
    /// XPC call cannot pin the daemon on an unbounded string.
    public static let maxTasksNoteBytes = 64 * 1024

    public static func allowsJSON(_ data: Data) -> Bool { data.count <= maxJSONBytes }
    public static func allowsFileBytes(_ count: Int) -> Bool { count <= maxFileBytes }
    public static func allowsShortString(_ s: String) -> Bool {
        s.utf8.count <= maxShortStringBytes
    }
    public static func allowsTasksNote(_ s: String) -> Bool {
        s.utf8.count <= maxTasksNoteBytes
    }
}
