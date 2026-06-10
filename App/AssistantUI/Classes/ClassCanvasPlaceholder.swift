import SwiftUI

/// The gray center canvas. In Phase 3 this becomes the interactive pin board.
struct ClassCanvasPlaceholder: View {
    var body: some View {
        ZStack {
            Color.primary.opacity(0.02)
            Text("Drag files here to pin previews (coming soon)")
                .font(.callout).foregroundStyle(.tertiary)
        }
    }
}
