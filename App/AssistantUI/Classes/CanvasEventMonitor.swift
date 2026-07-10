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
    /// Returns true when the delete was consumed (something was deleted).
    let onDelete: () -> Bool

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
        view.onDelete = onDelete
    }
}

final class CanvasEventCatcherView: NSView {
    var onPan: ((Double, Double) -> Void)?
    var onZoom: ((Double, CGPoint) -> Void)?
    var pdfTarget: ((CGPoint) -> PDFView?)?
    var onGestureEnd: (() -> Void)?
    var onDelete: (() -> Bool)?

    private var monitors: [Any] = []
    /// True while a middle-mouse pan is latched: the pointer is locked
    /// (frozen + hidden) and every drag delta pans, ignoring board bounds.
    private var isMiddlePanning = false

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
            matching: [.otherMouseDown, .otherMouseDragged, .otherMouseUp]) {
            [weak self] event in self?.handleMiddleMouse(event) ?? event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in self?.handleKeyDown(event) ?? event
        } as Any)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit { removeMonitors() }

    /// App switch mid-pan: restore the pointer AND persist the viewport —
    /// the interrupted drag never gets its otherMouseUp save.
    @objc private func appResignedActive() {
        guard isMiddlePanning else { return }
        endMiddlePan()
        onGestureEnd?()
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didResignActiveNotification, object: nil)
        endMiddlePan()
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
            if scrollGestureSettled(event) { onGestureEnd?() }
            return nil
        }
        if let pdf = pdfTarget?(point), let scroll = Self.firstScrollView(in: pdf) {
            scroll.scrollWheel(with: event)
            return nil
        }
        onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
        if scrollGestureSettled(event) { onGestureEnd?() }
        return nil
    }

    /// A scroll event that completes a gesture: trackpad phase ended/cancelled,
    /// momentum tail ended/cancelled, or a phase-less legacy mouse-wheel notch
    /// (each notch is a complete gesture of its own).
    private func scrollGestureSettled(_ event: NSEvent) -> Bool {
        if event.phase == .ended || event.phase == .cancelled { return true }
        if event.momentumPhase == .ended || event.momentumPhase == .cancelled { return true }
        return event.phase == [] && event.momentumPhase == []
    }

    private func handleMagnify(_ event: NSEvent) -> NSEvent? {
        guard let point = boardLocation(of: event) else { return event }
        onZoom?(1 + event.magnification, point)
        if event.phase == .ended || event.phase == .cancelled { onGestureEnd?() }
        return nil
    }

    private func handleMiddleMouse(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2 else { return event }
        switch event.type {
        case .otherMouseDown:
            // Latch only if the press starts on the board; after that,
            // bounds no longer matter — the pointer is locked anyway.
            guard boardLocation(of: event) != nil else { return event }
            beginMiddlePan()
            return nil
        case .otherMouseDragged:
            guard isMiddlePanning else { return event }
            onPan?(event.deltaX, event.deltaY)
            return nil
        case .otherMouseUp:
            guard isMiddlePanning else { return event }
            endMiddlePan()
            onGestureEnd?()
            return nil
        default:
            return event
        }
    }

    /// Delete/forward-delete removes the board selection — but never steals
    /// keystrokes from text editing (field editors are NSTextViews).
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 51 || event.keyCode == 117,
              let window, event.window === window else { return event }
        if window.firstResponder is NSTextView { return event }
        if onDelete?() == true { return nil }
        return event
    }

    /// Pointer lock for the duration of the drag: the cursor freezes and
    /// hides while raw deltas keep flowing, so the pan can't fall off the
    /// board edge. hide/unhide and associate/disassociate are balanced by
    /// the isMiddlePanning guard.
    private func beginMiddlePan() {
        guard !isMiddlePanning else { return }
        isMiddlePanning = true
        NSCursor.hide()
        _ = CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func endMiddlePan() {
        guard isMiddlePanning else { return }
        isMiddlePanning = false
        _ = CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
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
