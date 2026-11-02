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
                // Identity includes the resolved path. A restored tab is created
                // before the file list arrives, and FilePreviewView can't swap
                // its NSView from the "File unavailable" label once the URL exists.
                FileDocumentView(store: store, fileId: fileId)
                    .id(store.fileURL(forFileId: fileId)?.path ?? fileId)
            } else {
                ClassCanvasView(store: store)
            }
        }
    }
}
