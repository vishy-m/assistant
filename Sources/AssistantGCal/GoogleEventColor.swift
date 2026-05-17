import Foundation

/// Maps an arbitrary hex color to the nearest of Google Calendar's 11 fixed
/// event colors, returning the Google `colorId` string.
public enum GoogleEventColor {

    /// (colorId, hex) for Google Calendar's event-color palette.
    public static let palette: [(id: String, hex: String)] = [
        ("1", "7986CB"), ("2", "33B679"), ("3", "8E24AA"), ("4", "E67C73"),
        ("5", "F6BF26"), ("6", "F4511E"), ("7", "039BE5"), ("8", "616161"),
        ("9", "3F51B5"), ("10", "0B8043"), ("11", "D50000")
    ]

    public static func nearestColorId(toHex hex: String) -> String {
        let target = rgb(hex)
        var bestId = "8"
        var bestDistance = Double.greatestFiniteMagnitude
        for entry in palette {
            let c = rgb(entry.hex)
            let d = pow(c.r - target.r, 2) + pow(c.g - target.g, 2) + pow(c.b - target.b, 2)
            if d < bestDistance { bestDistance = d; bestId = entry.id }
        }
        return bestId
    }

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }
}
