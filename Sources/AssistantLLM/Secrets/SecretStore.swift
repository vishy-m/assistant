import Foundation

/// The secrets Assistant needs. Raw values are the variable names in `.env`.
public enum SecretKey: String, CaseIterable, Sendable {
    case claudeAPIKey = "ANTHROPIC_API_KEY"
    case openaiAPIKey = "OPENAI_API_KEY"
    case geminiAPIKey = "GEMINI_API_KEY"
    case gemmaHostedAPIKey = "GEMMA_HOSTED_API_KEY"
    case googleOAuthClientSecret = "GOOGLE_OAUTH_CLIENT_SECRET"
    case googleOAuthRefreshToken = "GOOGLE_OAUTH_REFRESH_TOKEN"
}

/// Reads and writes secrets in a `.env` file.
///
/// The file is re-read on every `get`, so hand edits take effect without
/// restarting the daemon. Writes are atomic (temp file + rename), keep the
/// file owner-only (0600), preserve comments and unknown keys, and write
/// through a symlink rather than replacing it — so one shared `.env` can be
/// symlinked into several worktrees.
public struct SecretStore: Sendable {

    /// Environment variable that points the daemon at its `.env` file. The
    /// LaunchAgent plist sets it to `<repo root>/.env`.
    public static let fileEnvironmentVariable = "ASSISTANT_ENV_FILE"

    /// Serialises read-modify-write cycles within this process. `flock` on
    /// the sidecar lock file (below) serialises them across processes.
    private static let writeLock = NSLock()

    public let fileURL: URL

    public init(fileURL: URL = SecretStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// `$ASSISTANT_ENV_FILE` if set, otherwise
    /// `~/Library/Application Support/Assistant/.env`.
    /// The advisory lock file every writer of `fileURL` holds from read
    /// through rename: `<resolved .env path>.lock`. It sits beside the real
    /// file (not the symlink), so every worktree sharing one `.env` agrees on
    /// it, and it is never replaced, unlike the `.env` inode itself.
    /// Scripts/migrate-keychain-to-env.sh takes the same lock.
    public static func lockFileURL(for fileURL: URL) -> URL {
        let resolved = resolvedFileURL(fileURL)
        return resolved.deletingLastPathComponent()
            .appendingPathComponent(resolved.lastPathComponent + ".lock")
    }

    /// Follows symlinks on the file itself, including one whose target
    /// doesn't exist yet (`resolvingSymlinksInPath` leaves those alone, which
    /// would make the first write replace the symlink with a plain file).
    static func resolvedFileURL(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        for _ in 0..<32 {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else {
                break
            }
            current = (dest.hasPrefix("/")
                ? URL(fileURLWithPath: dest)
                : current.deletingLastPathComponent().appendingPathComponent(dest)).standardizedFileURL
        }
        return current
    }

    public static func defaultFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let path = environment[fileEnvironmentVariable], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Assistant/.env")
    }

    /// The stored value, or nil if the key is missing or empty.
    public func get(_ key: SecretKey) throws -> String? {
        guard let value = try load().value(for: key.rawValue), !value.isEmpty else { return nil }
        return value
    }

    public func set(_ key: SecretKey, value: String) throws {
        try modify { $0.set(key.rawValue, value: value) }
    }

    public func delete(_ key: SecretKey) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try modify { $0.remove(key.rawValue) }
    }

    // MARK: - File IO

    private func load() throws -> EnvFile {
        do {
            return EnvFile(contents: try String(contentsOf: fileURL, encoding: .utf8))
        } catch CocoaError.fileReadNoSuchFile {
            return EnvFile(contents: "")
        }
    }

    private func modify(_ change: (inout EnvFile) -> Void) throws {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }

        let target = Self.resolvedFileURL(fileURL)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let lockFD = try Self.acquireFileLock(Self.lockFileURL(for: fileURL))
        defer {
            flock(lockFD, LOCK_UN)
            close(lockFD)
        }

        var env = try load()
        change(&env)
        try Self.atomicWrite(env.serialized(), to: target)
    }

    /// Opens (creating 0600 if needed) and exclusively `flock`s the lock file,
    /// blocking until other holders release it.
    private static func acquireFileLock(_ url: URL) throws -> Int32 {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SecretStoreError.io("open lock", errno) }
        fchmod(fd, 0o600)
        while flock(fd, LOCK_EX) != 0 {
            let err = errno
            if err == EINTR { continue }
            close(fd)
            throw SecretStoreError.io("flock", err)
        }
        return fd
    }

    private static func atomicWrite(_ text: String, to target: URL) throws {
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")

        // Create the temp file 0600 from the start so the secrets are never
        // briefly readable by other users.
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw SecretStoreError.io("open", errno) }
        var ok = false
        defer {
            if !ok { unlink(tmp.path) }
        }

        let bytes = Array(text.utf8)
        var written = 0
        while written < bytes.count {
            let n = bytes[written...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                let err = errno
                close(fd)
                throw SecretStoreError.io("write", err)
            }
            written += n
        }
        fchmod(fd, 0o600)
        fsync(fd)
        close(fd)

        guard rename(tmp.path, target.path) == 0 else {
            throw SecretStoreError.io("rename", errno)
        }
        ok = true
    }
}

public enum SecretStoreError: Error, CustomStringConvertible {
    case io(String, Int32)

    public var description: String {
        switch self {
        case let .io(op, code): return "\(op) failed: \(String(cString: strerror(code)))"
        }
    }
}
