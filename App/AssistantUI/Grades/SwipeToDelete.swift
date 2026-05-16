import SwiftUI

/// Wraps a row so a left-swipe reveals a Delete action. A long swipe removes
/// the row immediately; a short swipe parks the action open for a deliberate
/// tap. The content sits on an opaque layer so it cleanly covers the action.
struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var base: CGFloat = 0

    private let actionWidth: CGFloat = 78

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .opacity(offset < -1 ? 1 : 0)
            content
                .background(GradeTheme.windowBg)
                .offset(x: offset)
                .gesture(drag)
        }
        .clipped()
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: offset)
    }

    private var deleteAction: some View {
        Button(action: triggerDelete) {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text("Delete")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .background(Color(red: 0.71, green: 0.32, blue: 0.29))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                offset = min(0, max(base + value.translation.width, -actionWidth * 1.9))
            }
            .onEnded { value in
                let projected = base + value.translation.width
                if projected < -actionWidth * 1.5 {
                    triggerDelete()
                } else if projected < -actionWidth * 0.5 {
                    base = -actionWidth
                    offset = -actionWidth
                } else {
                    base = 0
                    offset = 0
                }
            }
    }

    private func triggerDelete() {
        base = 0
        offset = 0
        onDelete()
    }
}
