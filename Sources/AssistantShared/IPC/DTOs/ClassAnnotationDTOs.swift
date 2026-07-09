import Foundation
import CoreGraphics

/// What an annotation is. Stored as a raw string in the DTO/DB so unknown
/// future kinds degrade to "skip" instead of failing to decode.
public enum AnnotationKind: String, Codable {
    case stroke, shape, sticky, text
}

public enum AnnotationShape: String, Codable {
    case rect, ellipse, line, arrow
}

/// A board annotation: generic geometry envelope (world-space center + size,
/// stacking order) plus a kind-specific JSON `payload`. Mirrors ClassPinDTO's
/// role for pins.
public struct ClassAnnotationDTO: Codable, Identifiable, Equatable {
    public let id: String
    public let courseId: String
    public let kind: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let zOrder: Int
    public let payload: String

    public init(id: String, courseId: String, kind: String, x: Double, y: Double,
                width: Double, height: Double, zOrder: Int, payload: String) {
        self.id = id
        self.courseId = courseId
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.zOrder = zOrder
        self.payload = payload
    }
}

// MARK: - Typed payloads (serialized into `payload`)

/// Freehand pen stroke: absolute world-space points; the DTO's box caches the
/// bounding box for broad-phase hit testing.
public struct StrokePayload: Codable, Equatable {
    public var points: [[Double]]
    public var color: String
    public var lineWidth: Double
    public init(points: [[Double]], color: String, lineWidth: Double) {
        self.points = points; self.color = color; self.lineWidth = lineWidth
    }
}

/// Shape in the DTO's box. Line/arrow run corner-to-corner: leading-top →
/// trailing-bottom, or the other diagonal when `flipped`.
public struct ShapePayload: Codable, Equatable {
    public var shape: AnnotationShape
    public var strokeColor: String
    public var fillColor: String?
    public var lineWidth: Double
    public var flipped: Bool
    public init(shape: AnnotationShape, strokeColor: String, fillColor: String?,
                lineWidth: Double, flipped: Bool) {
        self.shape = shape; self.strokeColor = strokeColor
        self.fillColor = fillColor; self.lineWidth = lineWidth; self.flipped = flipped
    }
}

/// Sticky note. `color` is a named palette slot (BoardStyle resolves it) so
/// the palette can be tuned later without rewriting rows.
public struct StickyPayload: Codable, Equatable {
    public var text: String
    public var color: String
    public init(text: String, color: String) { self.text = text; self.color = color }
}

public struct TextPayload: Codable, Equatable {
    public var text: String
    public var fontSize: Double
    public var color: String
    public init(text: String, fontSize: Double, color: String) {
        self.text = text; self.fontSize = fontSize; self.color = color
    }
}

// MARK: - Helpers

public extension ClassAnnotationDTO {
    var annotationKind: AnnotationKind? { AnnotationKind(rawValue: kind) }

    /// World-space bounding rect (x/y are the center).
    var box: CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    /// nil on malformed payload — callers skip the annotation, never crash.
    func decodedPayload<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func encodePayload<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    func moved(x: Double, y: Double) -> ClassAnnotationDTO {
        ClassAnnotationDTO(id: id, courseId: courseId, kind: kind, x: x, y: y,
                           width: width, height: height, zOrder: zOrder, payload: payload)
    }

    func resized(width: Double, height: Double) -> ClassAnnotationDTO {
        ClassAnnotationDTO(id: id, courseId: courseId, kind: kind, x: x, y: y,
                           width: width, height: height, zOrder: zOrder, payload: payload)
    }

    func withPayload(_ payload: String) -> ClassAnnotationDTO {
        ClassAnnotationDTO(id: id, courseId: courseId, kind: kind, x: x, y: y,
                           width: width, height: height, zOrder: zOrder, payload: payload)
    }
}
