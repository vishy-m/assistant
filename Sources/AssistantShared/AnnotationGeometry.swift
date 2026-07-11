import Foundation
import CoreGraphics

/// Pure world-space geometry for board annotations: bounding boxes, kind-aware
/// hit testing, eraser sweeps, and move/resize point transforms. UI-free so
/// every routing decision is unit-testable.
public enum AnnotationGeometry {

    /// Bounding rect of a point cloud; degenerate spans padded to ≥ 1 world
    /// unit so hit tests and resize math never divide by zero.
    public static func boundingBox(of points: [[Double]]) -> CGRect? {
        let xs = points.compactMap { $0.count == 2 ? $0[0] : nil }
        let ys = points.compactMap { $0.count == 2 ? $0[1] : nil }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY,
                      width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    public static func point(_ p: CGPoint, isNearPolyline points: [[Double]],
                             tolerance: Double) -> Bool {
        let pts = points.filter { $0.count == 2 }
        guard pts.count >= 2 else { return false }
        for i in 0..<(pts.count - 1) {
            let a = CGPoint(x: pts[i][0], y: pts[i][1])
            let b = CGPoint(x: pts[i + 1][0], y: pts[i + 1][1])
            if distance(from: p, toSegment: a, b) <= tolerance { return true }
        }
        return false
    }

    public static func circle(center: CGPoint, radius: Double,
                              intersectsPolyline points: [[Double]]) -> Bool {
        point(center, isNearPolyline: points, tolerance: radius)
    }

    /// Kind-aware containment for select/erase routing. Malformed payloads
    /// and unknown kinds are never hit.
    public static func point(_ p: CGPoint, inside dto: ClassAnnotationDTO,
                             tolerance: Double) -> Bool {
        switch dto.annotationKind {
        case .stroke:
            guard let s = dto.decodedPayload(StrokePayload.self) else { return false }
            guard dto.box.insetBy(dx: -tolerance, dy: -tolerance).contains(p) else { return false }
            return point(p, isNearPolyline: s.points, tolerance: tolerance)
        case .shape:
            guard let sh = dto.decodedPayload(ShapePayload.self) else { return false }
            let box = dto.box
            switch sh.shape {
            case .rect:
                if sh.fillColor != nil { return box.contains(p) }
                return box.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
                    && !box.insetBy(dx: tolerance, dy: tolerance).contains(p)
            case .ellipse:
                // Normalized ellipse membership: r = (dx/a)² + (dy/b)².
                let a = box.width / 2, b = box.height / 2
                guard a > 0, b > 0 else { return false }
                let nx = (p.x - box.midX) / a, ny = (p.y - box.midY) / b
                let r = nx * nx + ny * ny
                if sh.fillColor != nil { return r <= 1 }
                let inner = max(0, 1 - tolerance / min(a, b) * 2)
                let outer = 1 + tolerance / min(a, b) * 2
                return r >= inner * inner && r <= outer * outer
            case .line, .arrow:
                let ends = lineEndpoints(in: box, flipped: sh.flipped)
                return distance(from: p, toSegment: ends.a, ends.b) <= tolerance
            }
        case .sticky, .text:
            return dto.box.contains(p)
        case nil:
            return false
        }
    }

    public static func translate(points: [[Double]], dx: Double, dy: Double) -> [[Double]] {
        points.map { $0.count == 2 ? [$0[0] + dx, $0[1] + dy] : $0 }
    }

    /// Rescale points from one box to another (stroke resize).
    public static func scale(points: [[Double]], from old: CGRect, to new: CGRect) -> [[Double]] {
        guard old.width > 0, old.height > 0 else { return points }
        let sx = new.width / old.width, sy = new.height / old.height
        return points.map {
            guard $0.count == 2 else { return $0 }
            return [new.minX + ($0[0] - old.minX) * sx,
                    new.minY + ($0[1] - old.minY) * sy]
        }
    }

    /// Line/arrow endpoints: box diagonal, top-leading → bottom-trailing, or
    /// bottom-leading → top-trailing when flipped.
    public static func lineEndpoints(in box: CGRect, flipped: Bool) -> (a: CGPoint, b: CGPoint) {
        flipped
            ? (CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.minY))
            : (CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY))
    }

    /// Frontmost stroke/shape under a world point (stickies/text have their
    /// own views and hit-test themselves).
    public static func topmostInk(at p: CGPoint, in dtos: [ClassAnnotationDTO],
                                  tolerance: Double) -> ClassAnnotationDTO? {
        dtos.filter { $0.annotationKind == .stroke || $0.annotationKind == .shape }
            .sorted { $0.zOrder > $1.zOrder }
            .first { point(p, inside: $0, tolerance: tolerance) }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSq = abx * abx + aby * aby
        guard lengthSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSq))
        return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby))
    }
}

public extension ClassAnnotationDTO {
    /// Stroke factory: caches the bounding box in the DTO envelope.
    /// nil when there are not at least two points (clicks draw nothing).
    static func stroke(id: String, courseId: String, points: [[Double]],
                       color: String, lineWidth: Double, zOrder: Int) -> ClassAnnotationDTO? {
        guard points.count >= 2,
              let box = AnnotationGeometry.boundingBox(of: points) else { return nil }
        return ClassAnnotationDTO(
            id: id, courseId: courseId, kind: AnnotationKind.stroke.rawValue,
            x: box.midX, y: box.midY, width: box.width, height: box.height,
            zOrder: zOrder,
            payload: encodePayload(StrokePayload(points: points, color: color,
                                                 lineWidth: lineWidth)))
    }
}
