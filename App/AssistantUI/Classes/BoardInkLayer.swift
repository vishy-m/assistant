import SwiftUI
import AssistantShared

/// Screen-space vector layer for strokes and shapes. World geometry maps
/// through the viewport per frame, so ink stays crisp at any zoom (no
/// scaleEffect rasterization) and never clips at a container edge.
struct BoardInkLayer: View {
    @ObservedObject var store: ClassStore
    @ObservedObject var editor: BoardEditor

    var body: some View {
        Canvas { context, _ in
            let viewport = store.viewport
            for dto in store.annotations.sorted(by: { $0.zOrder < $1.zOrder }) {
                draw(dto, in: &context, viewport: viewport)
            }
            drawLive(in: &context, viewport: viewport)
            drawSelection(in: &context, viewport: viewport)
        }
        .allowsHitTesting(false)
    }

    // MARK: committed annotations

    private func draw(_ dto: ClassAnnotationDTO, in context: inout GraphicsContext,
                      viewport: CanvasViewport) {
        let drag = dragOffset(for: dto.id)
        switch dto.annotationKind {
        case .stroke:
            guard let s = dto.decodedPayload(StrokePayload.self) else { return }
            let path = polylinePath(s.points, viewport: viewport, drag: drag)
            context.stroke(path, with: .color(BoardStyle.inkColor(s.color)),
                           style: strokeStyle(s.lineWidth, viewport: viewport))
        case .shape:
            guard let sh = dto.decodedPayload(ShapePayload.self) else { return }
            let box = dto.box.offsetBy(dx: drag.width, dy: drag.height)
            let screenBox = screenRect(box, viewport: viewport)
            let style = strokeStyle(sh.lineWidth, viewport: viewport)
            let stroke = BoardStyle.inkColor(sh.strokeColor)
            switch sh.shape {
            case .rect:
                let p = Path(screenBox)
                if let fill = sh.fillColor {
                    context.fill(p, with: .color(BoardStyle.color(hex: fill)))
                }
                context.stroke(p, with: .color(stroke), style: style)
            case .ellipse:
                let p = Path(ellipseIn: screenBox)
                if let fill = sh.fillColor {
                    context.fill(p, with: .color(BoardStyle.color(hex: fill)))
                }
                context.stroke(p, with: .color(stroke), style: style)
            case .line, .arrow:
                let ends = AnnotationGeometry.lineEndpoints(in: box, flipped: sh.flipped)
                let a = viewport.worldToScreen(ends.a)
                let b = viewport.worldToScreen(ends.b)
                var p = Path()
                p.move(to: a); p.addLine(to: b)
                context.stroke(p, with: .color(stroke), style: style)
                if sh.shape == .arrow {
                    let head = sh.reversed ? a : b
                    let tail = sh.reversed ? b : a
                    context.fill(arrowhead(from: tail, to: head,
                                           size: max(8, sh.lineWidth * 3) * viewport.zoom),
                                 with: .color(stroke))
                }
            }
        case .sticky, .text, nil:
            return // object layer / unknown kinds — not ink
        }
    }

    // MARK: live (uncommitted) drawing

    private func drawLive(in context: inout GraphicsContext, viewport: CanvasViewport) {
        if editor.liveStrokePoints.count >= 2 {
            let path = polylinePath(editor.liveStrokePoints, viewport: viewport, drag: .zero)
            context.stroke(path, with: .color(BoardStyle.inkColor(editor.penColor)),
                           style: strokeStyle(editor.penWidth, viewport: viewport))
        }
        if editor.tool == .shape, let start = editor.liveShapeStart,
           let current = editor.liveShapeCurrent {
            let box = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                             width: abs(start.x - current.x), height: abs(start.y - current.y))
            let flipped = (current.x - start.x) * (current.y - start.y) < 0
            let ends = AnnotationGeometry.lineEndpoints(in: box, flipped: flipped)
            let reversed = hypot(current.x - ends.a.x, current.y - ends.a.y)
                < hypot(current.x - ends.b.x, current.y - ends.b.y)
            let payload = ShapePayload(shape: editor.shapeKind,
                                       strokeColor: editor.shapeStrokeColor,
                                       fillColor: editor.shapeFilled ? editor.shapeStrokeColor : nil,
                                       lineWidth: editor.penWidth, flipped: flipped,
                                       reversed: reversed)
            let ghost = ClassAnnotationDTO(id: "live", courseId: "live",
                                           kind: AnnotationKind.shape.rawValue,
                                           x: box.midX, y: box.midY,
                                           width: box.width, height: box.height, zOrder: .max,
                                           payload: ClassAnnotationDTO.encodePayload(payload))
            draw(ghost, in: &context, viewport: viewport)
        }
    }

    private func drawSelection(in context: inout GraphicsContext, viewport: CanvasViewport) {
        for id in editor.selectedAnnotationIds {
            guard let dto = store.annotations.first(where: { $0.id == id }),
                  dto.annotationKind == .stroke || dto.annotationKind == .shape
            else { continue }
            let drag = dragOffset(for: id)
            let box = screenRect(dto.box.offsetBy(dx: drag.width, dy: drag.height)
                                     .insetBy(dx: -6, dy: -6), viewport: viewport)
            context.stroke(Path(roundedRect: box, cornerRadius: 4),
                           with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        drawMarquee(in: &context, viewport: viewport)
    }

    private func drawMarquee(in context: inout GraphicsContext, viewport: CanvasViewport) {
        guard editor.tool == .select,
              let start = editor.marqueeStart,
              let current = editor.marqueeCurrent else { return }
        let world = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                           width: abs(start.x - current.x), height: abs(start.y - current.y))
        let box = screenRect(world, viewport: viewport)
        context.fill(Path(box), with: .color(.accentColor.opacity(0.08)))
        context.stroke(Path(box), with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: helpers

    private func dragOffset(for id: String) -> CGSize {
        if let drag = editor.inkDrag, drag.id == id {
            return CGSize(width: drag.dx, height: drag.dy)
        }
        if let group = editor.selectionDrag, editor.selectedAnnotationIds.contains(id) {
            return group
        }
        return .zero
    }

    private func polylinePath(_ points: [[Double]], viewport: CanvasViewport,
                              drag: CGSize) -> Path {
        var path = Path()
        let pts = points.filter { $0.count == 2 }.map {
            viewport.worldToScreen(CGPoint(x: $0[0] + drag.width, y: $0[1] + drag.height))
        }
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }

    private func screenRect(_ world: CGRect, viewport: CanvasViewport) -> CGRect {
        let origin = viewport.worldToScreen(CGPoint(x: world.minX, y: world.minY))
        return CGRect(x: origin.x, y: origin.y,
                      width: world.width * viewport.zoom,
                      height: world.height * viewport.zoom)
    }

    private func strokeStyle(_ worldWidth: Double, viewport: CanvasViewport) -> StrokeStyle {
        StrokeStyle(lineWidth: max(0.5, worldWidth * viewport.zoom),
                    lineCap: .round, lineJoin: .round)
    }

    private func arrowhead(from a: CGPoint, to b: CGPoint, size: Double) -> Path {
        var path = Path()
        let angle = atan2(b.y - a.y, b.x - a.x)
        let tip = b
        let left = CGPoint(x: b.x - size * cos(angle - .pi / 7),
                           y: b.y - size * sin(angle - .pi / 7))
        let right = CGPoint(x: b.x - size * cos(angle + .pi / 7),
                            y: b.y - size * sin(angle + .pi / 7))
        path.move(to: tip); path.addLine(to: left); path.addLine(to: right); path.closeSubpath()
        return path
    }
}
