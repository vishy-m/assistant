import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import AssistantShared

/// The gray center pin board. Files dragged from the Files panel (carrying their
/// `file.id` as text) drop here to create an interactive pin at the drop point.
struct ClassCanvasView: View {
    @ObservedObject var store: ClassStore

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BoardGridLayer(viewport: store.viewport)
                    .contentShape(Rectangle())
                    .onTapGesture { store.focusedPinId = nil }

                BoardInkLayer(store: store, editor: store.board)

                if store.pins.isEmpty && store.annotations.isEmpty {
                    Text("Drag files from the left to pin previews here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                // The infinite "world" layer. Pins keep their world coordinates;
                // the viewport pans/zooms this whole layer. The "canvas" space
                // lives INSIDE the transform so PinView's gestures read back
                // world-space values unchanged at any zoom.
                ZStack {
                    ForEach(store.pins.sorted { $0.zOrder < $1.zOrder }) { pin in
                        PinView(
                            pin: pin,
                            fileName: store.filesById[pin.fileId]?.name ?? "File",
                            fileURL: store.fileURL(for: pin),
                            contentType: store.filesById[pin.fileId]?.contentType ?? "public.data",
                            pdfRegistry: store.pdfViews,
                            isFocused: store.focusedPinId == pin.id,
                            onCommit: { store.updatePin($0) },
                            onBringToFront: { store.bringPinToFront(id: pin.id) },
                            onFocus: { store.focusedPinId = pin.id },
                            onRemove: { store.deletePin(id: pin.id) },
                            onOpenExternally: {
                                if let url = store.fileURL(for: pin) { NSWorkspace.shared.open(url) }
                            },
                            onOpenInTab: { store.openFileTab(id: pin.fileId) }
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .coordinateSpace(name: "canvas")
                .scaleEffect(store.viewport.zoom, anchor: .topLeading)
                .offset(x: store.viewport.offsetX, y: store.viewport.offsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .background(eventMonitor)
            .background(resetShortcut(canvasSize: geo.size))
            .overlay(alignment: .bottomTrailing) { BoardZoomPill(store: store, canvasSize: geo.size) }
            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers, location in
                handleDrop(providers, at: store.viewport.screenToWorld(location))
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], at worldPoint: CGPoint) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) })
        else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let fileId = value as? String else { return }
            DispatchQueue.main.async {
                store.createPin(fileId: fileId, x: Double(worldPoint.x), y: Double(worldPoint.y))
            }
        }
        return true
    }

    /// ⌘0 → reset to 100% zoom centered on the pins. A zero-size hidden
    /// button is the lightest way to scope a keyboard shortcut to this view.
    private func resetShortcut(canvasSize: CGSize) -> some View {
        Button("") { store.resetViewport(canvasSize: canvasSize) }
            .keyboardShortcut("0", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// AppKit gesture layer: pan/zoom the viewport, forward scrolls over PDF
    /// pins into their PDFView, persist on gesture end.
    private var eventMonitor: some View {
        CanvasEventMonitorView(
            onPan: { dx, dy in
                store.viewport = store.viewport.panned(byScreenDeltaX: dx, deltaY: dy)
            },
            onZoom: { factor, anchor in
                store.viewport = store.viewport.zoomed(by: factor, at: anchor)
            },
            pdfTarget: { screenPoint in
                // Only a clicked-to-focus PDF pin captures scroll; otherwise
                // the board pans. Click empty canvas to release focus.
                guard let focusedId = store.focusedPinId else { return nil }
                let world = store.viewport.screenToWorld(screenPoint)
                let hit = CanvasHitTesting.topmostPin(at: world, in: store.pins) { pin in
                    guard pin.id == focusedId,
                          let file = store.filesById[pin.fileId] else { return false }
                    return FilePreviewKind.from(contentType: file.contentType) == .pdf
                }
                guard let hit else { return nil }
                return store.pdfViews.view(forPin: hit.id)
            },
            onGestureEnd: { store.saveViewport() }
        )
    }
}
