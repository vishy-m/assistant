import AppKit

/// Borderless, non-activating panel pinned to the bottom of the active screen.
final class OverlayPanel: NSPanel {

    /// Width of the overlay in points (matches spec §5.1).
    static let preferredWidth: CGFloat = 720

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        self.isFloatingPanel = true
        self.level = .statusBar          // Above normal windows, below screen-saver
        self.collectionBehavior = [.canJoinAllSpaces,
                                    .stationary,
                                    .ignoresCycle]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.animationBehavior = .utilityWindow
        self.hidesOnDeactivate = false   // we manage dismiss ourselves
        self.isReleasedWhenClosed = false
    }

    // Borderless windows refuse key by default. We need it for text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Position the panel centered horizontally, 24pt above the dock-aware visibleFrame bottom.
    func anchorToBottom(of screen: NSScreen? = nil) {
        let scr = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = scr?.visibleFrame else { return }
        let size = frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 24
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Resize to a target height; reposition to stay anchored.
    func updateHeight(_ height: CGFloat, animated: Bool) {
        let scr = NSScreen.main ?? NSScreen.screens.first
        let visible = scr?.visibleFrame ?? .zero
        let newRect = NSRect(x: visible.midX - frame.width / 2,
                             y: visible.minY + 24,
                             width: frame.width,
                             height: height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                animator().setFrame(newRect, display: true)
            }
        } else {
            setFrame(newRect, display: true)
        }
    }
}
