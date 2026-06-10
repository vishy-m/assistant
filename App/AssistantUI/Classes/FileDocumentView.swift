import SwiftUI
import AssistantShared

/// Full-canvas interactive preview of one open file tab. Reuses FilePreviewView
/// (scrollable PDF / Quick Look / "File unavailable" fallback).
struct FileDocumentView: View {
    @ObservedObject var store: ClassStore
    let fileId: String

    var body: some View {
        FilePreviewView(url: store.fileURL(forFileId: fileId),
                        contentType: store.file(id: fileId)?.contentType ?? "public.data")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
