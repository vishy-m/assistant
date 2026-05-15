import AppKit

@MainActor
final class CropSelectionController {

    static let shared = CropSelectionController()

    private var window: NSWindow?
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var continuation: CheckedContinuation<NSRect?, Never>?

    private init() {}

    /// Show a full-screen dim with crosshair cursor; resolve with the user's selection
    /// in global screen coordinates, or nil if the user cancels.
    func selectRegion() async -> NSRect? {
        await withCheckedContinuation { (cont: CheckedContinuation<NSRect?, Never>) in
            self.continuation = cont
            self.show()
        }
    }

    private func show() {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { resolve(nil); return }

        let frame = screen.frame
        let w = NSWindow(contentRect: frame,
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        w.level = .screenSaver
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.acceptsMouseMovedEvents = true

        let view = CropView()
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.onMouseDown = { [weak self] point in self?.startPoint = point }
        view.onMouseDragged = { [weak self] point in
            guard let self, let start = self.startPoint else { return }
            self.currentRect = Self.makeRect(from: start, to: point)
            view.selectionRect = self.currentRect
            view.needsDisplay = true
        }
        view.onMouseUp = { [weak self] _ in
            guard let self else { return }
            let global = view.window?.convertToScreen(self.currentRect) ?? self.currentRect
            self.hide()
            self.resolve(global.width > 4 && global.height > 4 ? global : nil)
        }
        view.onEscape = { [weak self] in
            self?.hide()
            self?.resolve(nil)
        }
        w.contentView = view
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
        self.window = w
    }

    private func hide() {
        NSCursor.arrow.set()
        window?.orderOut(nil)
        window = nil
        startPoint = nil
        currentRect = .zero
    }

    private func resolve(_ rect: NSRect?) {
        let c = continuation
        continuation = nil
        c?.resume(returning: rect)
    }

    private static func makeRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

private final class CropView: NSView {

    var selectionRect: NSRect = .zero

    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }
    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        onMouseUp?(convert(event.locationInWindow, from: nil))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }   // Esc
        else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if selectionRect.width > 0 && selectionRect.height > 0 {
            NSColor.clear.setFill()
            let clear = selectionRect
            // Punch a clear hole
            NSGraphicsContext.saveGraphicsState()
            let path = NSBezierPath(rect: clear)
            NSColor.clear.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.white.setStroke()
            let stroke = NSBezierPath(rect: clear.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }
}
