import Foundation

/// Client-minted Google Calendar event ids.
///
/// Google accepts a caller-supplied `id` on insert if it uses base32hex
/// characters (`0-9`, `a-v`) and is 5–1024 characters long; it must be unique
/// per calendar. A lowercase UUID with the hyphens removed (32 hex digits) fits.
/// Minting the id before the first POST lets a retry reuse it, so a lost
/// response cannot produce a duplicate event.
public enum GCalEventID {
    public static func mint() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
