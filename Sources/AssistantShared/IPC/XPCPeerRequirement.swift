import Foundation
import Security

/// Builds a code-signing requirement string used to authenticate an XPC peer
/// via `NSXPCConnection.setCodeSigningRequirement(_:)`.
///
/// In a Developer-ID / distribution-signed build it pins the Apple anchor plus
/// the team identifier — unforgeable. In an ad-hoc / unsigned dev build there
/// is no anchor to pin, so it falls back to a signing-identifier match: that
/// still rejects arbitrary unsigned processes, which is the realistic local
/// threat, while keeping the dev build working.
public enum XPCPeerRequirement {

    /// `identifier` is the expected signing identifier of the peer (its bundle
    /// identifier for an app target).
    public static func string(forIdentifier identifier: String) -> String {
        let base = "identifier \"\(identifier)\""
        guard let team = ownTeamIdentifier(), !team.isEmpty else {
            return base
        }
        return "anchor apple generic and \(base) and certificate leaf[subject.OU] = \"\(team)\""
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
