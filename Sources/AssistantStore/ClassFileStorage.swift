import Foundation

/// Owns the on-disk bytes for class files. Not sandboxed, so files live next to
/// the database: <base>/<courseId>/<storedName>. `base` is injectable for tests.
public struct ClassFileStorage {
    public let base: URL
    public init(base: URL) { self.base = base }

    /// Production base: ~/Library/Application Support/Assistant/ClassFiles
    public static func defaultBase() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return support.appendingPathComponent("Assistant/ClassFiles", isDirectory: true)
    }

    public func courseDir(_ courseId: String) -> URL {
        base.appendingPathComponent(courseId, isDirectory: true)
    }

    public func fileURL(courseId: String, storedName: String) -> URL {
        courseDir(courseId).appendingPathComponent(storedName)
    }

    @discardableResult
    public func write(_ data: Data, courseId: String, storedName: String) throws -> URL {
        let dir = courseDir(courseId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(storedName)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func remove(courseId: String, storedName: String) throws {
        let url = fileURL(courseId: courseId, storedName: storedName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
