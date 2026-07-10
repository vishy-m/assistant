import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import AssistantShared

/// The gray center pin board. Files dragged from the Files panel (carrying their
/// `file.id` as text) drop here to create an interactive pin at the drop point.
struct ClassCanvasView: View {
    @ObservedObject var store: ClassStore
    /// Observed separately: nested ObservableObjects don't forward changes
    /// through ClassStore, and this body reads board.tool / selection to
    /// mount the capture overlay and resize handle. Same instance as
    /// store.board — the property exists purely for the subscription.
    @ObservedObject var board: BoardEditor
    /// One hit test per select-gesture: set on the first onChanged event.
    @State private var inkGestureHitTested = false
    /// The current grid-layer drag is moving the whole selection (it started
    /// on an already-selected ink annotation).
    @State private var inkGroupDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BoardGridLayer(viewport: store.viewport)
                    .contentShape(Rectangle())
                    .gesture(inkSelectGesture)

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
                    ForEach(store.annotations
                        .filter { $0.annotationKind == .sticky || $0.annotationKind == .text }
                        .sorted { $0.zOrder < $1.zOrder }) { dto in
                        BoardObjectView(dto: dto, store: store, editor: store.board)
                    }

                    ForEach(store.pins.sorted { $0.zOrder < $1.zOrder }) { pin in
                        PinView(
                            pin: pin,
                            fileName: store.filesById[pin.fileId]?.name ?? "File",
                            fileURL: store.fileURL(for: pin),
                            contentType: store.filesById[pin.fileId]?.contentType ?? "public.data",
                            pdfRegistry: store.pdfViews,
                            isFocused: store.focusedPinId == pin.id,
                            isSelected: store.board.selectedPinIds.contains(pin.id),
                            groupDragOffset: store.board.selectedPinIds.contains(pin.id)
                                ? (store.board.selectionDrag ?? .zero) : .zero,
                            onGroupDragChanged: { store.board.selectionDrag = $0 },
                            onGroupDragEnded: { translation in
                                store.board.selectionDrag = nil
                                store.moveSelection(
                                    annotationIds: store.board.selectedAnnotationIds,
                                    pinIds: store.board.selectedPinIds,
                                    dx: translation.width, dy: translation.height)
                            },
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
                .allowsHitTesting(store.board.tool == .select)
                .coordinateSpace(name: "canvas")
                .scaleEffect(store.viewport.zoom, anchor: .topLeading)
                .offset(x: store.viewport.offsetX, y: store.viewport.offsetY)

                if store.board.tool != .select {
                    BoardCaptureOverlay(store: store, editor: store.board)
                }

                if store.board.tool == .select { selectedInkHandle }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .background(eventMonitor)
            .background(resetShortcut(canvasSize: geo.size))
            .background(undoShortcuts)
            .overlay(alignment: .bottomTrailing) { BoardZoomPill(store: store, canvasSize: geo.size) }
            .overlay(alignment: .leading) { BoardToolbar(store: store, editor: store.board) }
            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers, location in
                handleDrop(providers, at: store.viewport.screenToWorld(location))
            }
            .onExitCommand {
                if store.board.editingAnnotationId != nil {
                    store.board.editingAnnotationId = nil
                } else if store.board.hasSelection {
                    store.board.selectedAnnotationIds = []
                    store.board.selectedPinIds = []
                } else {
                    store.board.tool = .select
                }
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

    /// ⌘Z / ⇧⌘Z, board-scoped like ⌘0. Disabled while a text editor is
    /// focused so typing undo stays with the text system.
    private var undoShortcuts: some View {
        Group {
            Button("") { store.undoBoard() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store.board.editingAnnotationId != nil)
            Button("") { store.redoBoard() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store.board.editingAnnotationId != nil)
        }
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
            onGestureEnd: { store.saveViewport() },
            onDelete: {
                guard store.board.tool == .select,
                      store.board.editingAnnotationId == nil else { return false }
                if store.board.hasSelection {
                    let annotationIds = store.board.selectedAnnotationIds
                    let pinIds = store.board.selectedPinIds
                    store.board.selectedAnnotationIds = []
                    store.board.selectedPinIds = []
                    store.deleteSelection(annotationIds: annotationIds, pinIds: pinIds)
                    return true
                }
                if let pinId = store.focusedPinId {
                    store.focusedPinId = nil
                    store.deletePin(id: pinId)
                    return true
                }
                return false
            }
        )
    }

    /// Select-mode interactions for ink (strokes/shapes), which have no views
    /// of their own: click selects, drag moves. Runs on the grid layer, which
    /// is what clicks land on when they miss every pin/object view. Also
    /// clears pin focus / annotation selection on empty-canvas clicks.
    private var inkSelectGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard store.board.tool == .select else { return }
                if !inkGestureHitTested {
                    inkGestureHitTested = true
                    let world = store.viewport.screenToWorld(value.startLocation)
                    if let hit = AnnotationGeometry.topmostInk(
                        at: world, in: store.annotations,
                        tolerance: BoardStyle.hitTolerance / store.viewport.zoom) {
                        if store.board.selectedAnnotationIds.contains(hit.id),
                           store.board.selectionCount > 1 {
                            inkGroupDragging = true
                        } else {
                            store.board.selectedAnnotationIds = [hit.id]
                            store.board.selectedPinIds = []
                            store.board.inkDrag = (id: hit.id, dx: 0, dy: 0)
                        }
                    } else {
                        store.board.marqueeStart = world
                    }
                }
                let worldDx = value.translation.width / store.viewport.zoom
                let worldDy = value.translation.height / store.viewport.zoom
                if inkGroupDragging {
                    store.board.selectionDrag = CGSize(width: worldDx, height: worldDy)
                } else if let drag = store.board.inkDrag {
                    store.board.inkDrag = (id: drag.id, dx: worldDx, dy: worldDy)
                } else if store.board.marqueeStart != nil {
                    store.board.marqueeCurrent = store.viewport.screenToWorld(value.location)
                }
            }
            .onEnded { value in
                guard store.board.tool == .select else {
                    inkGestureHitTested = false
                    inkGroupDragging = false
                    store.board.inkDrag = nil
                    store.board.marqueeStart = nil
                    store.board.marqueeCurrent = nil
                    store.board.selectionDrag = nil
                    return
                }
                defer {
                    store.board.inkDrag = nil
                    store.board.marqueeStart = nil
                    store.board.marqueeCurrent = nil
                    store.board.selectionDrag = nil
                    inkGestureHitTested = false
                    inkGroupDragging = false
                }
                let worldDx = value.translation.width / store.viewport.zoom
                let worldDy = value.translation.height / store.viewport.zoom
                if inkGroupDragging {
                    if abs(worldDx) + abs(worldDy) > 1 {
                        store.moveSelection(annotationIds: store.board.selectedAnnotationIds,
                                            pinIds: store.board.selectedPinIds,
                                            dx: worldDx, dy: worldDy)
                    }
                    return
                }
                if let drag = store.board.inkDrag {
                    if abs(worldDx) + abs(worldDy) > 1 {
                        moveInkAnnotation(id: drag.id, dx: worldDx, dy: worldDy)
                    }
                    return
                }
                if let start = store.board.marqueeStart {
                    let end = store.viewport.screenToWorld(value.location)
                    let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                      width: abs(start.x - end.x), height: abs(start.y - end.y))
                    if rect.width + rect.height > 4 {
                        selectMarquee(rect)
                        return
                    }
                }
                // True click on empty canvas (or a tiny marquee): select what's
                // under it or clear everything.
                let world = store.viewport.screenToWorld(value.location)
                if let hit = AnnotationGeometry.topmostInk(
                    at: world, in: store.annotations,
                    tolerance: BoardStyle.hitTolerance / store.viewport.zoom) {
                    store.board.selectedAnnotationIds = [hit.id]
                    store.board.selectedPinIds = []
                } else {
                    store.board.selectedAnnotationIds = []
                    store.board.selectedPinIds = []
                    store.board.editingAnnotationId = nil
                    store.focusedPinId = nil
                }
            }
    }

    /// Marquee select: everything whose bounds intersect the world rect.
    private func selectMarquee(_ rect: CGRect) {
        store.board.selectedAnnotationIds = Set(
            store.annotations.filter { $0.box.intersects(rect) }.map(\.id))
        store.board.selectedPinIds = Set(
            store.pins.filter { CanvasHitTesting.boundingBox(of: $0).intersects(rect) }.map(\.id))
        store.board.editingAnnotationId = nil
    }

    private func moveInkAnnotation(id: String, dx: Double, dy: Double) {
        guard let dto = store.annotations.first(where: { $0.id == id }) else { return }
        if dto.annotationKind == .stroke,
           var payload = dto.decodedPayload(StrokePayload.self) {
            payload.points = AnnotationGeometry.translate(points: payload.points, dx: dx, dy: dy)
            store.updateAnnotation(
                dto.moved(x: dto.x + dx, y: dto.y + dy)
                    .withPayload(ClassAnnotationDTO.encodePayload(payload)))
        } else {
            store.updateAnnotation(dto.moved(x: dto.x + dx, y: dto.y + dy))
        }
    }

    /// Screen-space resize handle at the selected ink annotation's
    /// bottom-trailing corner (ink lives in a Canvas, so the handle is the
    /// one interactive view it gets).
    @ViewBuilder private var selectedInkHandle: some View {
        if let id = store.board.soleSelectedAnnotationId,
           let dto = store.annotations.first(where: { $0.id == id }),
           dto.annotationKind == .stroke || dto.annotationKind == .shape,
           store.board.inkDrag == nil, store.board.selectionDrag == nil {
            let corner = store.viewport.worldToScreen(
                CGPoint(x: dto.box.maxX, y: dto.box.maxY))
            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(x: corner.x + 8, y: corner.y + 8)
                .gesture(inkResizeGesture(dto: dto))
        }
    }

    private func inkResizeGesture(dto: ClassAnnotationDTO) -> some Gesture {
        DragGesture()
            .onEnded { value in
                let old = dto.box
                let new = CGRect(x: old.minX, y: old.minY,
                                 width: max(8, old.width + value.translation.width / store.viewport.zoom),
                                 height: max(8, old.height + value.translation.height / store.viewport.zoom))
                var updated = dto
                    .moved(x: new.midX, y: new.midY)
                    .resized(width: new.width, height: new.height)
                if dto.annotationKind == .stroke,
                   var payload = dto.decodedPayload(StrokePayload.self) {
                    payload.points = AnnotationGeometry.scale(points: payload.points,
                                                              from: old, to: new)
                    updated = updated.withPayload(ClassAnnotationDTO.encodePayload(payload))
                }
                store.updateAnnotation(updated)
            }
    }
}
