import Foundation

/// A minimal `.env` parser/editor that preserves everything it doesn't touch
/// (comments, blank lines, ordering, unknown keys), so the app can write a
/// file the user also edits by hand.
///
/// Supported syntax: `KEY=value`, optional `export ` prefix, `#` comment
/// lines, ` # trailing comments` on unquoted values, `"double"` quotes (with
/// `\"`, `\\` and `\n` escapes) and `'single'` quotes (literal).
struct EnvFile {

    private enum Line {
        case other(String)
        case entry(key: String, value: String, raw: String)
    }

    private var lines: [Line]

    init(contents: String) {
        var raw = contents.components(separatedBy: "\n")
        if raw.last == "" { raw.removeLast() }   // trailing newline, not a blank line
        lines = raw.map { line in
            let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if let (key, value) = Self.parse(line) {
                return .entry(key: key, value: value, raw: line)
            }
            return .other(line)
        }
    }

    /// The value of the last assignment to `key`, matching shell semantics.
    func value(for key: String) -> String? {
        for line in lines.reversed() {
            if case let .entry(k, v, _) = line, k == key { return v }
        }
        return nil
    }

    /// Replaces the first assignment to `key` in place (dropping any later
    /// duplicates), or appends one if the key isn't present.
    mutating func set(_ key: String, value: String) {
        let newLine = Line.entry(key: key, value: value, raw: "\(key)=\(Self.encode(value))")
        var replaced = false
        lines = lines.compactMap { line in
            guard case let .entry(k, _, _) = line, k == key else { return line }
            if replaced { return nil }
            replaced = true
            return newLine
        }
        if !replaced { lines.append(newLine) }
    }

    mutating func remove(_ key: String) {
        lines.removeAll { line in
            if case let .entry(k, _, _) = line { return k == key }
            return false
        }
    }

    func serialized() -> String {
        guard !lines.isEmpty else { return "" }
        return lines.map { line -> String in
            switch line {
            case let .other(raw): return raw
            case let .entry(_, _, raw): return raw
            }
        }.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing

    private static func parse(_ line: String) -> (String, String)? {
        var rest = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
        if rest.isEmpty || rest.hasPrefix("#") { return nil }
        if rest.hasPrefix("export ") { rest = rest.dropFirst("export ".count) }

        guard let eq = rest.firstIndex(of: "=") else { return nil }
        let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
        guard isValidKey(key) else { return nil }

        let rawValue = rest[rest.index(after: eq)...].drop(while: { $0 == " " || $0 == "\t" })
        return (key, decode(rawValue))
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else { return false }
        return key.unicodeScalars.allSatisfy {
            $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0))
        }
    }

    private static func decode(_ raw: Substring) -> String {
        if raw.hasPrefix("\"") {
            var out = ""
            var escaping = false
            for ch in raw.dropFirst() {
                if escaping {
                    switch ch {
                    case "n": out.append("\n")
                    case "\"", "\\": out.append(ch)
                    default: out.append("\\"); out.append(ch)
                    }
                    escaping = false
                } else if ch == "\\" {
                    escaping = true
                } else if ch == "\"" {
                    return out
                } else {
                    out.append(ch)
                }
            }
            return out   // unterminated quote: be lenient, keep what we have
        }
        if raw.hasPrefix("'") {
            let body = raw.dropFirst()
            return String(body.firstIndex(of: "'").map { body[..<$0] } ?? body)
        }
        // Unquoted: a `#` preceded by whitespace starts a comment.
        var value = raw
        var prev: Character = " "
        for idx in raw.indices {
            if raw[idx] == "#" && (prev == " " || prev == "\t") {
                value = raw[..<idx]
                break
            }
            prev = raw[idx]
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Encoding

    private static let bareSafe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:+=@,%~"
    )

    private static func encode(_ value: String) -> String {
        if value.unicodeScalars.allSatisfy({ bareSafe.contains($0) }) { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
