import SwiftUI
import AppKit
import PDFKit
import Quartz
import AssistantShared

/// Renders a file's interactive preview: PDFView for PDFs (scroll + page nav),
/// QLPreviewView for everything else, and a fallback label if bytes are missing.
struct FilePreviewView: NSViewRepresentable {
    let url: URL?
    let contentType: String

    func makeNSView(context: Context) -> NSView {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return Self.unavailableView()
        }
        switch FilePreviewKind.from(contentType: contentType) {
        case .pdf:
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.document = PDFDocument(url: url)
            return view
        case .quickLook:
            guard let preview = QLPreviewView(frame: .zero, style: .normal) else {
                return Self.unavailableView()
            }
            preview.previewItem = url as NSURL
            preview.autostarts = true
            return preview
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        if let pdf = nsView as? PDFView {
            if pdf.document?.documentURL != url { pdf.document = PDFDocument(url: url) }
        } else if let preview = nsView as? QLPreviewView {
            if (preview.previewItem as? NSURL) as URL? != url { preview.previewItem = url as NSURL }
        }
    }

    private static func unavailableView() -> NSView {
        let label = NSTextField(labelWithString: "File unavailable")
        label.alignment = .center
        label.textColor = .tertiaryLabelColor
        label.font = .systemFont(ofSize: 11)
        let container = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
