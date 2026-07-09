import AppKit
import PDFKit

/// Live PDFViews on the board, keyed by pin id, so canvas-level scroll events
/// can be forwarded into the right document (the previews themselves are
/// hit-test-disabled to keep drag-anywhere pin movement). Values are weak:
/// a dismantled preview drops out automatically.
final class PDFViewRegistry {
    private let table = NSMapTable<NSString, PDFView>.strongToWeakObjects()

    func register(_ view: PDFView, forPin id: String) {
        table.setObject(view, forKey: id as NSString)
    }

    func unregister(pin id: String) {
        table.removeObject(forKey: id as NSString)
    }

    func view(forPin id: String) -> PDFView? {
        table.object(forKey: id as NSString)
    }
}
