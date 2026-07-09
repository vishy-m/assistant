import Foundation
import CoreGraphics

/// The class board's pan/zoom state: a pure mapping between "world"
/// coordinates (where pins live, unbounded) and "screen" coordinates (the
/// visible canvas, origin top-leading). screen = world * zoom + offset.
/// Kept out of the UI so the math is unit-testable, like PinLayout.
public struct CanvasViewport: Codable, Equatable {
    public static let minZoom: Double = 0.25
    public static let maxZoom: Double = 4.0

    public private(set) var offsetX: Double
    public private(set) var offsetY: Double
    public private(set) var zoom: Double

    /// Non-finite inputs fall back to the identity viewport's values; zoom is
    /// clamped so a corrupt persisted value can never wedge the board.
    public init(offsetX: Double = 0, offsetY: Double = 0, zoom: Double = 1) {
        self.offsetX = offsetX.isFinite ? offsetX : 0
        self.offsetY = offsetY.isFinite ? offsetY : 0
        self.zoom = zoom.isFinite ? min(max(zoom, Self.minZoom), Self.maxZoom) : 1
    }

    private enum CodingKeys: String, CodingKey { case offsetX, offsetY, zoom }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(offsetX: try c.decode(Double.self, forKey: .offsetX),
                  offsetY: try c.decode(Double.self, forKey: .offsetY),
                  zoom: try c.decode(Double.self, forKey: .zoom))
    }

    public func worldToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + offsetX, y: p.y * zoom + offsetY)
    }

    public func screenToWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offsetX) / zoom, y: (p.y - offsetY) / zoom)
    }

    public func panned(byScreenDeltaX dx: Double, deltaY dy: Double) -> CanvasViewport {
        guard dx.isFinite, dy.isFinite else { return self }
        return CanvasViewport(offsetX: offsetX + dx, offsetY: offsetY + dy, zoom: zoom)
    }

    /// Multiplies zoom by `factor`, keeping the world point under the screen
    /// `anchor` stationary (zoom-at-cursor).
    public func zoomed(by factor: Double, at anchor: CGPoint) -> CanvasViewport {
        guard factor.isFinite, factor > 0, anchor.x.isFinite, anchor.y.isFinite else { return self }
        let newZoom = min(max(zoom * factor, Self.minZoom), Self.maxZoom)
        let ratio = newZoom / zoom
        return CanvasViewport(offsetX: anchor.x - (anchor.x - offsetX) * ratio,
                              offsetY: anchor.y - (anchor.y - offsetY) * ratio,
                              zoom: newZoom)
    }

    /// 100% zoom with the given world point at the center of the canvas —
    /// the ⌘0 "reset view" target.
    public static func centered(onWorldX x: Double, worldY y: Double,
                                canvasSize: CGSize) -> CanvasViewport {
        CanvasViewport(offsetX: canvasSize.width / 2 - x,
                       offsetY: canvasSize.height / 2 - y,
                       zoom: 1)
    }
}
