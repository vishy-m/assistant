import SwiftUI
import AssistantShared

/// Owns left-mouse drags while a creation/erase tool is active (the world
/// layer is hit-transparent then). Screen locations convert to world points;
/// commits go through ClassStore (which records history). Pan/zoom/middle
/// mouse stay with the NSEvent monitor and work in every tool.
struct BoardCaptureOverlay: View {
    @ObservedObject var store: ClassStore
    @ObservedObject var editor: BoardEditor

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onHover { inside in
                if inside && editor.isDrawingTool { NSCursor.crosshair.set() }
                else { NSCursor.arrow.set() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let world = store.viewport.screenToWorld(value.location)
                switch editor.tool {
                case .pen:
                    editor.liveStrokePoints.append([Double(world.x), Double(world.y)])
                case .eraser:
                    erase(at: world)
                case .shape:
                    if editor.liveShapeStart == nil {
                        editor.liveShapeStart = store.viewport.screenToWorld(value.startLocation)
                    }
                    editor.liveShapeCurrent = world
                case .sticky, .text, .select:
                    break
                }
            }
            .onEnded { value in
                let world = store.viewport.screenToWorld(value.location)
                switch editor.tool {
                case .pen: commitStroke()
                case .eraser: break
                case .shape: commitShape()
                case .sticky: placeSticky(at: world)
                case .text: placeText(at: world)
                case .select: break
                }
            }
    }

    // MARK: pen

    private func commitStroke() {
        defer { editor.liveStrokePoints = [] }
        guard let dto = ClassAnnotationDTO.stroke(
            id: UUID().uuidString,
            courseId: currentCourseId ?? "",
            points: editor.liveStrokePoints,
            color: editor.penColor,
            lineWidth: editor.penWidth,
            zOrder: store.nextAnnotationZOrder()),
            !dto.courseId.isEmpty else { return }
        store.createAnnotation(dto)
    }

    // MARK: eraser

    /// Eraser sweep: removes ANY annotation under the point (kind-aware
    /// containment with the eraser radius as tolerance — strokes keep their
    /// polyline-intersection precision) and any pin under it. Everything is
    /// undoable through the unified history.
    private func erase(at world: CGPoint) {
        let victims = store.annotations.filter {
            AnnotationGeometry.point(world, inside: $0,
                                     tolerance: BoardStyle.eraserWorldRadius)
        }
        for dto in victims {
            editor.selectedAnnotationIds.remove(dto.id)
            if editor.editingAnnotationId == dto.id { editor.editingAnnotationId = nil }
            store.deleteAnnotation(id: dto.id)
        }
        for pin in store.pins where CanvasHitTesting.point(world, inside: pin) {
            if store.focusedPinId == pin.id { store.focusedPinId = nil }
            editor.selectedPinIds.remove(pin.id)
            store.deletePin(id: pin.id)
        }
    }

    // MARK: shape / sticky / text

    private func commitShape() {
        defer { editor.liveShapeStart = nil; editor.liveShapeCurrent = nil }
        guard let start = editor.liveShapeStart, let end = editor.liveShapeCurrent,
              let courseId = currentCourseId else { return }
        let width = abs(start.x - end.x), height = abs(start.y - end.y)
        guard width + height > 4 else { return } // a click is not a shape
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: max(width, 1), height: max(height, 1))
        let flipped = (end.x - start.x) * (end.y - start.y) < 0
        // Arrowheads track the drag END: box+flipped picks the diagonal,
        // `reversed` picks which of its endpoints is the head.
        let ends = AnnotationGeometry.lineEndpoints(in: box, flipped: flipped)
        let reversed = hypot(end.x - ends.a.x, end.y - ends.a.y)
            < hypot(end.x - ends.b.x, end.y - ends.b.y)
        let payload = ShapePayload(shape: editor.shapeKind,
                                   strokeColor: editor.shapeStrokeColor,
                                   fillColor: editor.shapeFilled ? editor.shapeStrokeColor : nil,
                                   lineWidth: editor.penWidth,
                                   flipped: flipped,
                                   reversed: reversed)
        store.createAnnotation(ClassAnnotationDTO(
            id: UUID().uuidString, courseId: courseId,
            kind: AnnotationKind.shape.rawValue,
            x: (start.x + end.x) / 2, y: (start.y + end.y) / 2,
            width: max(width, 1), height: max(height, 1),
            zOrder: store.nextAnnotationZOrder(),
            payload: ClassAnnotationDTO.encodePayload(payload)))
    }

    private func placeSticky(at world: CGPoint) {
        guard let courseId = currentCourseId else { return }
        let dto = ClassAnnotationDTO(
            id: UUID().uuidString, courseId: courseId,
            kind: AnnotationKind.sticky.rawValue,
            x: world.x, y: world.y, width: 160, height: 160,
            zOrder: store.nextAnnotationZOrder(),
            payload: ClassAnnotationDTO.encodePayload(
                StickyPayload(text: "", color: editor.stickyColor)))
        store.createAnnotation(dto)
        editor.selectedAnnotationIds = [dto.id]
        editor.selectedPinIds = []
        editor.editingAnnotationId = dto.id
        editor.tool = .select // place one, then type/move — FigJam behavior
    }

    private func placeText(at world: CGPoint) {
        guard let courseId = currentCourseId else { return }
        let dto = ClassAnnotationDTO(
            id: UUID().uuidString, courseId: courseId,
            kind: AnnotationKind.text.rawValue,
            x: world.x, y: world.y, width: 240, height: 44,
            zOrder: store.nextAnnotationZOrder(),
            payload: ClassAnnotationDTO.encodePayload(
                TextPayload(text: "", fontSize: editor.textSize, color: editor.textColor)))
        store.createAnnotation(dto)
        editor.selectedAnnotationIds = [dto.id]
        editor.selectedPinIds = []
        editor.editingAnnotationId = dto.id
        editor.tool = .select
    }

    private var currentCourseId: String? {
        let id = store.detail?.id ?? "" // ClassDetail.id IS the course id
        return id.isEmpty ? nil : id
    }
}
