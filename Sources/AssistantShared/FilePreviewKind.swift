import Foundation
import UniformTypeIdentifiers

/// Which preview engine renders a file, decided purely from its UTI string.
/// PDF-conforming types use the dedicated PDF branch; everything else (and any
/// unrecognized type) falls back to the system Quick Look preview.
public enum FilePreviewKind: Equatable {
    case pdf
    case quickLook

    public static func from(contentType: String) -> FilePreviewKind {
        if let type = UTType(contentType), type.conforms(to: .pdf) { return .pdf }
        return .quickLook
    }
}
