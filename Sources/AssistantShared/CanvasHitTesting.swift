import Foundation
import CoreGraphics

/// Pure world-space geometry for routing canvas events to pins (e.g. "is the
/// cursor over a PDF pin?"). Rotation-aware because pins can be rotated.
public enum CanvasHitTesting {
    /// Whether a world-space point falls inside a pin's (possibly rotated)
    /// card. Works by rotating the point into the pin's local frame.
    public static func point(_ p: CGPoint, inside pin: ClassPinDTO) -> Bool {
        let dx = Double(p.x) - pin.x
        let dy = Double(p.y) - pin.y
        let cosR = cos(-pin.rotation)
        let sinR = sin(-pin.rotation)
        let localX = dx * cosR - dy * sinR
        let localY = dx * sinR + dy * cosR
        return abs(localX) <= pin.width / 2 && abs(localY) <= pin.height / 2
    }

    /// The frontmost pin under a world-space point that satisfies `matching`,
    /// or nil. Frontmost = highest zOrder, same as the render stacking.
    public static func topmostPin(at p: CGPoint, in pins: [ClassPinDTO],
                                  matching: (ClassPinDTO) -> Bool) -> ClassPinDTO? {
        pins.sorted { $0.zOrder > $1.zOrder }
            .first { matching($0) && point(p, inside: $0) }
    }

    /// Axis-aligned bounding box of a (possibly rotated) pin — the marquee
    /// intersection test runs against this.
    public static func boundingBox(of pin: ClassPinDTO) -> CGRect {
        let halfW = pin.width / 2, halfH = pin.height / 2
        let cosR = abs(cos(pin.rotation)), sinR = abs(sin(pin.rotation))
        let extentX = halfW * cosR + halfH * sinR
        let extentY = halfW * sinR + halfH * cosR
        return CGRect(x: pin.x - extentX, y: pin.y - extentY,
                      width: extentX * 2, height: extentY * 2)
    }
}
