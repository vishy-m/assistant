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
                    eraseStrokes(at: world)
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
            courseId: store.detail?.id ?? "",
            points: editor.liveStrokePoints,
            color: editor.penColor,
            lineWidth: editor.penWidth,
            zOrder: store.nextAnnotationZOrder()),
            !dto.courseId.isEmpty else { return }
        store.createAnnotation(dto)
    }

    // MARK: eraser

    private func eraseStrokes(at world: CGPoint) {
        let victims = store.annotations.filter { dto in
            guard dto.annotationKind == .stroke,
                  let s = dto.decodedPayload(StrokePayload.self) else { return false }
            guard dto.box.insetBy(dx: -BoardStyle.eraserWorldRadius,
                                  dy: -BoardStyle.eraserWorldRadius).contains(world)
            else { return false }
            return AnnotationGeometry.circle(center: world,
                                             radius: BoardStyle.eraserWorldRadius,
                                             intersectsPolyline: s.points)
        }
        for dto in victims { store.deleteAnnotation(id: dto.id) }
    }

    // MARK: shape / sticky / text — completed in the next task

    private func commitShape() {
        editor.liveShapeStart = nil
        editor.liveShapeCurrent = nil
    }

    private func placeSticky(at world: CGPoint) {}
    private func placeText(at world: CGPoint) {}
}
