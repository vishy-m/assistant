import SwiftUI
import AssistantShared

/// Bottom-trailing zoom readout: − / percentage / +. Steps anchor at the
/// canvas center; clicking the percentage resets like ⌘0.
struct BoardZoomPill: View {
    @ObservedObject var store: ClassStore
    let canvasSize: CGSize

    private var center: CGPoint { CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2) }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                store.viewport = store.viewport.zoomed(by: 0.8, at: center)
                store.saveViewport()
            } label: { Image(systemName: "minus") }
            Button {
                store.resetViewport(canvasSize: canvasSize)
            } label: {
                Text("\(Int((store.viewport.zoom * 100).rounded()))%")
                    .font(GradeTheme.mono(11))
                    .frame(minWidth: 40)
            }
            .help("Reset view (⌘0)")
            Button {
                store.viewport = store.viewport.zoomed(by: 1.25, at: center)
                store.saveViewport()
            } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1)))
        .padding(12)
    }
}
