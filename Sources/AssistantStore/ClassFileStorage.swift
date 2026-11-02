import Foundation

/// Owns the on-disk bytes for class files. Not sandboxed, so files live next to
/// the database: <base>/<courseId>/<storedName>. `base` is injectable for tests.
///
/// `courseId` and `storedName` arrive over XPC and from database rows, so every
/// mutating call goes through `resolve`, which only accepts single, plain path
/// components and refuses a course directory that resolves anywhere other than
/// directly under `base` (e.g. a planted symlink).
public struct ClassFileStorage {
    public enum StorageError: Error, Equatable {
        /// The component is empty, `.`, `..`, contains `/`, `\` or NUL, or is too long.
        case unsafeComponent(String)
        /// The course directory does not resolve to `<base>/<courseId>`.
        case escapesBase(String)
    }

    public let base: URL
    public init(base: URL) { self.base = base }

    /// Production base: ~/Library/Application Support/Assistant/ClassFiles
    public static func defaultBase() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return support.appendingPathComponent("Assistant/ClassFiles", isDirectory: true)
    }

    /// True if `s` is one plain path component that cannot step out of its parent.
    public static func isSafeComponent(_ s: String) -> Bool {
        guard !s.isEmpty, s != ".", s != "..", s.utf8.count <= 255 else { return false }
        return !s.contains(where: { $0 == "/" || $0 == "\\" || $0 == "\0" })
    }

    public func courseDir(_ courseId: String) -> URL {
        base.appendingPathComponent(courseId, isDirectory: true)
    }

    /// Unchecked URL for reading in the UI. Mutations use `resolve`.
    public func fileURL(courseId: String, storedName: String) -> URL {
        courseDir(courseId).appendingPathComponent(storedName)
    }

    /// Validates both components and returns `<base>/<courseId>/<storedName>`.
    /// If the course directory already exists it must resolve to exactly that
    /// path under the resolved `base` (no symlinked course dirs).
    public func resolve(courseId: String, storedName: String) throws -> URL {
        let dir = try resolveCourseDir(courseId)
        guard Self.isSafeComponent(storedName) else {
            throw StorageError.unsafeComponent(storedName)
        }
        return dir.appendingPathComponent(storedName, isDirectory: false)
    }

    /// Atomic write that replaces an existing file at the same name.
    @discardableResult
    public func write(_ data: Data, courseId: String, storedName: String) throws -> URL {
        let url = try resolve(courseId: courseId, storedName: storedName)
        try ensureCourseDir(courseId)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Exclusive create: fails if anything (including a symlink) already exists
    /// at the destination, so it can never overwrite another file's bytes.
    @discardableResult
    public func writeNew(_ data: Data, courseId: String, storedName: String) throws -> URL {
        let url = try resolve(courseId: courseId, storedName: storedName)
        try ensureCourseDir(courseId)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return url
    }

    /// Removes the file. Missing file (or missing course dir) is not an error.
    public func remove(courseId: String, storedName: String) throws {
        let url = try resolve(courseId: courseId, storedName: storedName)
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return }   // nothing there
        try FileManager.default.removeItem(at: url)
    }

    /// Cleanup helper for metadata deletes. Returns true when the bytes are gone
    /// afterwards: removed now, already missing, or the names are unsafe and so
    /// can never address a file under `base` (legacy rows). Returns false only
    /// on a real I/O failure, so the caller keeps the row for a retry.
    public func discard(courseId: String, storedName: String) -> Bool {
        do {
            try remove(courseId: courseId, storedName: storedName)
            return true
        } catch StorageError.unsafeComponent {
            return true
        } catch {
            return false
        }
    }

    /// Removes `<base>/<courseId>` and anything left inside it. Missing is fine.
    public func removeCourseDirectory(courseId: String) throws {
        let dir = try resolveCourseDir(courseId)
        var st = stat()
        guard lstat(dir.path, &st) == 0 else { return }
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: - Private

    private func resolveCourseDir(_ courseId: String) throws -> URL {
        guard Self.isSafeComponent(courseId) else { throw StorageError.unsafeComponent(courseId) }
        let dir = courseDir(courseId)
        var st = stat()
        if lstat(dir.path, &st) == 0 {
            // Must be a real directory whose canonical path is <realpath(base)>/<courseId>.
            guard (st.st_mode & S_IFMT) == S_IFDIR,
                  let realDir = Self.realPath(dir.path),
                  let realBase = Self.realPath(base.path),
                  realDir == realBase + "/" + courseId
            else { throw StorageError.escapesBase(courseId) }
        }
        return dir
    }

    /// Creates `base` (trusted, may need intermediates) and then the single
    /// course directory under it, re-checking containment afterwards.
    private func ensureCourseDir(_ courseId: String) throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dir = courseDir(courseId)
        if mkdir(dir.path, 0o755) != 0 && errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        _ = try resolveCourseDir(courseId)
    }

    private static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
