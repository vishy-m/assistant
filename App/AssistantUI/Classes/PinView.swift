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
    let pdfRegistry: PDFViewRegistry?
    let isFocused: Bool
    let onCommit: (ClassPinDTO) -> Void
    let onBringToFront: () -> Void
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onOpenExternally: () -> Void
    let onOpenInTab: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var liveSize: CGSize?
    @State private var liveRotation: Double?

    private var size: CGSize { liveSize ?? CGSize(width: pin.width, height: pin.height) }
    private var rotation: Double { liveRotation ?? pin.rotation }
    private var previewKind: FilePreviewKind { FilePreviewKind.from(contentType: contentType) }
    /// Focus is only meaningful on PDF pins (it captures scroll for reading),
    /// so only they show the ring.
    private var showsFocusRing: Bool { isFocused && previewKind == .pdf }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            pinPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The preview is click-transparent so the entire pin is one
                // uniform drag surface. Click a PDF pin to focus it, then
                // scroll to read; "Open in Tab" remains the full reader.
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(showsFocusRing ? Color.accentColor : Color.black.opacity(0.18),
                    lineWidth: showsFocusRing ? 2 : 1))
        .shadow(radius: 4, y: 2)
        // Drag anywhere on the card to move it; the handles (overlays, drawn on
        // top) keep their own resize/rotate gestures.
        .contentShape(Rectangle())
        .gesture(moveGesture)
        // PDFs don't rotate: a tilted scroll surface reads badly, so the
        // handle is hidden for them (existing stored rotations still render).
        .overlay(alignment: .top) { if previewKind != .pdf { rotateHandle } }
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .rotationEffect(.radians(rotation))
        .position(x: pin.x + dragOffset.width, y: pin.y + dragOffset.height)
        .onTapGesture { onBringToFront(); onFocus() }
        .contextMenu {
            Button("Open in Tab") { onOpenInTab() }
            Button("Open Externally") { onOpenExternally() }
            Divider()
            Button("Remove Pin", role: .destructive) { onRemove() }
        }
    }

    private var titleBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(fileName).font(GradeTheme.mono(10)).lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Images render as pure SwiftUI so they scale exactly with the pin chrome
    /// under the canvas zoom transform — QLPreviewView (an opaque AppKit view)
    /// lays out its content by its own rules and drifts under scaleEffect.
    @ViewBuilder private var pinPreview: some View {
        if previewKind == .image {
            ImagePinPreview(url: fileURL)
        } else {
            FilePreviewView(url: fileURL, contentType: contentType,
                            pinId: pin.id, registry: pdfRegistry)
                // Rebuild when the URL resolves: on app relaunch pins render
                // before the class's file list arrives, and FilePreviewView
                // can't swap engines (label -> PDFView) in updateNSView.
                .id(fileURL)
        }
    }

    // Drag the card to move. Canvas-space translation stays correct under rotation.
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

/// Pure-SwiftUI image preview for board pins. Loaded once per URL; missing
/// bytes degrade to the same "File unavailable" label as FilePreviewView.
struct ImagePinPreview: View {
    let url: URL?

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("File unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        guard let url, let loaded = NSImage(contentsOf: url) else {
            image = nil
            return
        }
        image = loaded
    }
}
