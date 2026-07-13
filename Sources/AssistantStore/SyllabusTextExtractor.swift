import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Plain-text extraction for syllabus scanning: PDFs via PDFKit, text-like
/// types via UTF-8 read. Anything else (or empty/unreadable content) is nil —
/// the scan reports "nothing to scan" instead of failing.
public enum SyllabusTextExtractor {
    public static let maxCharacters = 60_000

    public static func extract(url: URL, contentType: String) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let type = UTType(contentType)
        let raw: String?
        if type?.conforms(to: .pdf) == true {
            raw = PDFDocument(url: url)?.string
        } else if type?.conforms(to: .text) == true {
            raw = try? String(contentsOf: url, encoding: .utf8)
        } else {
            raw = nil
        }
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(maxCharacters))
    }
}
