import AppKit
import CoreGraphics

enum ScreenshotCapturer {

    /// Captures `rect` (in global screen coordinates, AppKit convention — origin at lower-left
    /// of the primary display). Returns NSImage + JPEG data, or nil on failure.
    static func capture(rect: CGRect) -> (image: NSImage, jpeg: Data)? {
        // Find the screen that contains the midpoint of the rect
        let mid = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mid) }) ?? NSScreen.main else {
            return nil
        }
        let displayID = screen.displayID
        // CG coordinates: origin at top-left of the screen; we have AppKit (bottom-left).
        // Convert.
        let cgRect = convertToCGScreenRect(rect, on: screen)

        guard let cgImage = CGDisplayCreateImage(displayID, rect: cgRect) else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: rect.size)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }
        return (nsImage, jpeg)
    }

    private static func convertToCGScreenRect(_ r: CGRect, on screen: NSScreen) -> CGRect {
        let screenH = screen.frame.height
        let yFromTop = screenH - r.maxY + screen.frame.minY  // accounts for multi-display offset
        return CGRect(x: r.minX - screen.frame.minX, y: yFromTop, width: r.width, height: r.height)
    }
}

private extension NSScreen {
    /// The CGDirectDisplayID for this NSScreen.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}
