import Foundation

/// Pure helpers for placing pins on the canvas: stacking order and the default
/// geometry of a freshly-dropped pin. Kept out of the UI so it can be unit-tested.
public enum PinLayout {
    /// Default card size for a newly-dropped pin, in points.
    public static let defaultWidth: Double = 280
    public static let defaultHeight: Double = 360

    /// One above the current frontmost pin (so a new/raised pin lands on top).
    public static func nextZOrder(_ pins: [ClassPinDTO]) -> Int {
        (pins.map(\.zOrder).max() ?? -1) + 1
    }

    /// A pin centered at `(x, y)` with the default size, no rotation.
    public static func makePin(id: String, courseId: String, fileId: String,
                               x: Double, y: Double, zOrder: Int) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: courseId, fileId: fileId,
                    x: x, y: y, width: defaultWidth, height: defaultHeight,
                    rotation: 0, zOrder: zOrder)
    }
}
