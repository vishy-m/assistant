import Foundation
import Security

/// Builds a code-signing requirement string used to authenticate an XPC peer
/// via `NSXPCConnection.setCodeSigningRequirement(_:)`.
///
/// A Developer ID build pins the Apple anchor and the team identifier. An
/// ad-hoc build has no team, so the requirement pins the on-disk Assistant UI
/// cdhash instead. Identifier-only matching is rejected: another same-user
/// process can embed `com.vishruth.assistant` with `codesign -s -`.
public enum XPCPeerRequirement {

    /// Requirement from an explicit team and peer cdhash. Tests inject both so
    /// they do not depend on the runner's signature.
    ///
    /// A non-empty team wins. With no team, a cdhash is required. Both absent
    /// returns nil — the caller must not resume the connection.
    public static func string(forIdentifier identifier: String,
                              team: String?,
                              peerCDHash: String?) -> String? {
        let hashes = peerCDHash.map { [$0] } ?? []
        return string(forIdentifier: identifier, team: team, peerCDHashes: hashes)
    }

    /// Production requirement. Uses this process's team when it has one, and
    /// otherwise the cdhash of `uiBinaryURL` (re-read on every call).
    public static func string(forIdentifier identifier: String,
                              uiBinaryURL: URL?) -> String? {
        let team = ownTeamIdentifier()
        let hashes: [String]
        if let team, !team.isEmpty {
            hashes = []
        } else if let uiBinaryURL {
            hashes = cdHashHexes(at: uiBinaryURL)
        } else {
            hashes = []
        }
        return string(forIdentifier: identifier, team: team, peerCDHashes: hashes)
    }

    /// `ASSISTANT_UI_BINARY` when set, otherwise the sibling `AssistantUI.app`
    /// of the helper executable. Xcode places both in `BUILT_PRODUCTS_DIR`.
    public static func resolvedUIBinaryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL
    ) -> URL? {
        if let override = environment["ASSISTANT_UI_BINARY"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        guard let executableURL else { return nil }
        return executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("AssistantUI.app")
    }

    /// Lowercase hex cdhashes from `kSecCodeInfoCdHashes`. Empty when the path
    /// is missing or unsigned. SHA-1 is 40 hex chars; SHA-256 is 64.
    static func cdHashHexes(at url: URL) -> [String] {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let raw = dict[kSecCodeInfoCdHashes as String] else { return [] }
        return hashData(from: raw).compactMap { data in
            guard !data.isEmpty else { return nil }
            return data.map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func string(forIdentifier identifier: String,
                               team: String?,
                               peerCDHashes: [String]) -> String? {
        let id = escape(identifier)
        if let team, !team.isEmpty {
            return "anchor apple generic and identifier \"\(id)\" and certificate leaf[subject.OU] = \"\(escape(team))\""
        }
        let clauses = peerCDHashes.map(escape).filter { !$0.isEmpty }.map { "cdhash H\"\($0)\"" }
        guard !clauses.isEmpty else { return nil }
        let hashClause = clauses.count == 1 ? clauses[0] : "(" + clauses.joined(separator: " or ") + ")"
        return "identifier \"\(id)\" and \(hashClause)"
    }

    /// Requirement-language string escape: `\` then `"`.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func hashData(from raw: Any) -> [Data] {
        if let datas = raw as? [Data] { return datas }
        if let datas = raw as? [NSData] { return datas.map { $0 as Data } }
        if let array = raw as? NSArray {
            return array.compactMap { item in
                if let data = item as? Data { return data }
                if let data = item as? NSData { return data as Data }
                return nil
            }
        }
        return []
    }

    /// The team identifier of the *current* process, or nil for ad-hoc/unsigned.
    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
