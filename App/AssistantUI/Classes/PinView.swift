import SwiftUI
import AppKit
import AssistantShared

/// A single interactive pin on the class canvas. Geometry is committed to the
/// store on gesture end; `x`/`y` are the card center in the "canvas" space.
struct PinView: View {
    let pin: ClassPinDTO
    let fileName: String
    let fileURL: URL?
    let contentType: String
    let onCommit: (ClassPinDTO) -> Void
    let onBringToFront: () -> Void
    let onRemove: () -> Void
    let onOpenExternally: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var liveSize: CGSize?
    @State private var liveRotation: Double?

    private var size: CGSize { liveSize ?? CGSize(width: pin.width, height: pin.height) }
    private var rotation: Double { liveRotation ?? pin.rotation }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            FilePreviewView(url: fileURL, contentType: contentType)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.18)))
        .shadow(radius: 4, y: 2)
        .overlay(alignment: .top) { rotateHandle }
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .rotationEffect(.radians(rotation))
        .position(x: pin.x + dragOffset.width, y: pin.y + dragOffset.height)
        .onTapGesture { onBringToFront() }
    }

    private var titleBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(fileName).font(GradeTheme.mono(10)).lineLimit(1)
            Spacer(minLength: 4)
            Menu {
                Button("Open Externally") { onOpenExternally() }
                Button("Remove Pin", role: .destructive) { onRemove() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .gesture(moveGesture)
    }

    // Drag the title bar to move. Canvas-space translation stays correct under rotation.
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                // Raise the pin once, at the start of the drag, so grabbing a
                // half-covered pin brings it forward as you move it.
                if dragOffset == .zero { onBringToFront() }
                dragOffset = value.translation
            }
            .onEnded { value in
                let committed = pin.moved(x: pin.x + value.translation.width,
                                          y: pin.y + value.translation.height)
                dragOffset = .zero
                onCommit(committed)
            }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 14, height: 14)
            .offset(x: 5, y: 5)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        liveSize = CGSize(width: max(140, pin.width + value.translation.width),
                                          height: max(140, pin.height + value.translation.height))
                    }
                    .onEnded { _ in
                        if let s = liveSize { onCommit(pin.resized(width: s.width, height: s.height)) }
                        liveSize = nil
                    }
            )
    }

    private var rotateHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 14, height: 14)
            .offset(y: -20)
            .gesture(
                DragGesture(coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        // Absolute-angle ("grab and swing") rotation: the card's top
                        // edge tracks the cursor. Because the handle sits at the current
                        // top, grabbing it reads back the existing rotation (no snap);
                        // swinging it around the center rotates the card. The +pi/2 maps
                        // "pointer straight up" (12 o'clock) to rotation 0.
                        let angle = atan2(value.location.y - pin.y, value.location.x - pin.x)
                        liveRotation = angle + .pi / 2
                    }
                    .onEnded { _ in
                        if let r = liveRotation { onCommit(pin.rotated(r)) }
                        liveRotation = nil
                    }
            )
    }
}
