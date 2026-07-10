import SwiftUI
import AssistantShared

/// FigJam-style dotted grid, drawn in screen space from the viewport. World
/// spacing starts at BoardStyle.gridBaseSpacing and doubles until the screen
/// spacing stays ≥ 12pt, so zooming out never turns the board to noise.
struct BoardGridLayer: View {
    let viewport: CanvasViewport

    var body: some View {
        Canvas { context, size in
            var spacing = BoardStyle.gridBaseSpacing * viewport.zoom
            guard spacing > 0.01 else { return }
            while spacing < 12 { spacing *= 2 }
            let dot = 1.5
            // First dot at the world-grid line nearest to screen origin.
            let startX = viewport.offsetX.truncatingRemainder(dividingBy: spacing)
            let startY = viewport.offsetY.truncatingRemainder(dividingBy: spacing)
            let color = Color.secondary.opacity(0.28)
            var x = startX - spacing
            while x < size.width + spacing {
                var y = startY - spacing
                while y < size.height + spacing {
                    context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2,
                                                        width: dot, height: dot)),
                                 with: .color(color))
                    y += spacing
                }
                x += spacing
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
