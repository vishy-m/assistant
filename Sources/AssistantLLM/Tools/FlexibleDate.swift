import Foundation

/// Parses the date/time strings an LLM is likely to emit for tool arguments.
/// `ISO8601DateFormatter` alone is too strict — it rejects fractional seconds
/// and offset-less timestamps, both of which models produce routinely.
public enum FlexibleDate {

    public static func parse(_ string: String?) -> Date? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        // ISO-8601 with offset/Z, with and without fractional seconds.
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }

        // Offset-less or space-separated forms — interpreted in the local zone.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        for pattern in ["yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                        "yyyy-MM-dd'T'HH:mm:ss",
                        "yyyy-MM-dd HH:mm:ss",
                        "yyyy-MM-dd HH:mm",
                        "yyyy-MM-dd"] {
            df.dateFormat = pattern
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }
}
