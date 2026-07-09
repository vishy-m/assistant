import SwiftUI
import AppKit
import PDFKit

/// Invisible AppKit layer behind the class board that supplies the gestures
/// SwiftUI can't see: two-finger scroll pans the canvas (or scrolls the PDF
/// pin under the cursor), pinch and ⌘-scroll zoom at the cursor, and
/// middle-mouse drag always pans — even over pins. `hitTest` returns nil so
/// clicks and drags pass straight through to the SwiftUI pins.
struct CanvasEventMonitorView: NSViewRepresentable {
    let onPan: (Double, Double) -> Void
    let onZoom: (Double, CGPoint) -> Void
    let pdfTarget: (CGPoint) -> PDFView?
    let onGestureEnd: () -> Void

    func makeNSView(context: Context) -> CanvasEventCatcherView {
        let view = CanvasEventCatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CanvasEventCatcherView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: CanvasEventCatcherView) {
        view.onPan = onPan
        view.onZoom = onZoom
        view.pdfTarget = pdfTarget
        view.onGestureEnd = onGestureEnd
    }
}

final class CanvasEventCatcherView: NSView {
    var onPan: ((Double, Double) -> Void)?
    var onZoom: ((Double, CGPoint) -> Void)?
    var pdfTarget: ((CGPoint) -> PDFView?)?
    var onGestureEnd: (() -> Void)?

    private var monitors: [Any] = []

    /// Flipped so converted event locations use a top-left origin, matching
    /// SwiftUI's coordinate space (and CanvasViewport's math).
    override var isFlipped: Bool { true }

    /// Never intercept clicks — pins keep their SwiftUI gestures.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitors()
        guard window != nil else { return }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in self?.handleScroll(event) ?? event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .magnify) {
            [weak self] event in self?.handleMagnify(event) ?? event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseDragged, .otherMouseUp]) {
            [weak self] event in self?.handleMiddleMouse(event) ?? event
        } as Any)
    }

    deinit { removeMonitors() }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    /// The event's location in this view's flipped coordinates, or nil when
    /// the event belongs to another window or falls outside the board.
    private func boardLocation(of event: NSEvent) -> CGPoint? {
        guard let window, event.window === window else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point) ? point : nil
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard let point = boardLocation(of: event) else { return event }
        if event.modifierFlags.contains(.command) {
            // ~100pt of scroll doubles/halves the zoom.
            onZoom?(pow(2, event.scrollingDeltaY / 100), point)
            if event.phase == .ended { onGestureEnd?() }
            return nil
        }
        if let pdf = pdfTarget?(point), let scroll = Self.firstScrollView(in: pdf) {
            scroll.scrollWheel(with: event)
            return nil
        }
        onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
        if event.phase == .ended || event.momentumPhase == .ended { onGestureEnd?() }
        return nil
    }

    private func handleMagnify(_ event: NSEvent) -> NSEvent? {
        guard let point = boardLocation(of: event) else { return event }
        onZoom?(1 + event.magnification, point)
        if event.phase == .ended { onGestureEnd?() }
        return nil
    }

    private func handleMiddleMouse(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2, boardLocation(of: event) != nil else { return event }
        if event.type == .otherMouseDragged {
            onPan?(event.deltaX, event.deltaY)
            return nil
        }
        onGestureEnd?() // otherMouseUp: gesture settled — persist.
        return nil
    }

    /// PDFView scrolls via an internal NSScrollView; find it so forwarded
    /// wheel events actually move the document.
    static func firstScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews {
            if let scroll = sub as? NSScrollView { return scroll }
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }
}
