import Foundation
import UniformTypeIdentifiers

/// Which preview engine renders a file, decided purely from its UTI string.
/// PDF-conforming types use the dedicated PDF branch; image-conforming types
/// use the SwiftUI image branch on the board; everything else (and any
/// unrecognized type) falls back to the system Quick Look preview.
public enum FilePreviewKind: Equatable {
    case pdf
    case image
    case quickLook

    public static func from(contentType: String) -> FilePreviewKind {
        guard let type = UTType(contentType) else { return .quickLook }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        return .quickLook
    }
}
