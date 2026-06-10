import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AssistantShared

/// The gray center pin board. Files dragged from the Files panel (carrying their
/// `file.id` as text) drop here to create an interactive pin at the drop point.
struct ClassCanvasView: View {
    @ObservedObject var store: ClassStore

    var body: some View {
        ZStack {
            Color.primary.opacity(0.02)

            if store.pins.isEmpty {
                Text("Drag files from the left to pin previews here")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            ForEach(store.pins.sorted { $0.zOrder < $1.zOrder }) { pin in
                PinView(
                    pin: pin,
                    fileName: store.filesById[pin.fileId]?.name ?? "File",
                    fileURL: store.fileURL(for: pin),
                    contentType: store.filesById[pin.fileId]?.contentType ?? "public.data",
                    onCommit: { store.updatePin($0) },
                    onBringToFront: { store.bringPinToFront(id: pin.id) },
                    onRemove: { store.deletePin(id: pin.id) },
                    onOpenExternally: {
                        if let url = store.fileURL(for: pin) { NSWorkspace.shared.open(url) }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .coordinateSpace(name: "canvas")
        .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers, location in
            handleDrop(providers, at: location)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) })
        else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let fileId = value as? String else { return }
            DispatchQueue.main.async {
                store.createPin(fileId: fileId, x: Double(location.x), y: Double(location.y))
            }
        }
        return true
    }
}
