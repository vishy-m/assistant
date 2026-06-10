import SwiftUI
import AssistantShared

/// The class canvas center: a tab bar over either the pin board (Board tab) or
/// the active file's full-canvas preview.
struct ClassCanvasContainer: View {
    @ObservedObject var store: ClassStore

    var body: some View {
        VStack(spacing: 0) {
            ClassCanvasTabBar(store: store)
            Divider()
            if let fileId = store.tabs.activeFileId {
                // .id(fileId) forces a fresh preview per file so switching between
                // a PDF and a non-PDF tab rebuilds the NSView instead of showing
                // stale content (FilePreviewView can't swap engines in updateNSView).
                FileDocumentView(store: store, fileId: fileId)
                    .id(fileId)
            } else {
                ClassCanvasView(store: store)
            }
        }
    }
}
