import SwiftUI

/// Single source of truth for board annotation styling: palettes, widths,
/// sizes, and interaction constants. Values are spec'd; change here only.
enum BoardStyle {
    /// Ink palette (pen, shape stroke, text): near-black, red, blue, green, orange.
    static let inkColors: [String] = ["#1D1D1F", "#E5484D", "#2E90FA", "#17B26A", "#F79009"]
    static let penWidths: [Double] = [2, 4, 8]

    /// Sticky palette slots — names persist in payloads; colors resolve here.
    static let stickySlots: [String] = ["yellow", "pink", "blue", "green", "orange"]

    static let textSizes: [(name: String, size: Double)] = [("S", 14), ("M", 20), ("L", 32)]

    static let eraserWorldRadius: Double = 12
    static let hitTolerance: Double = 10
    static let gridBaseSpacing: Double = 24

    static func stickyColor(_ slot: String) -> Color {
        switch slot {
        case "pink":   return Color(red: 1.00, green: 0.80, blue: 0.87)
        case "blue":   return Color(red: 0.78, green: 0.89, blue: 1.00)
        case "green":  return Color(red: 0.81, green: 0.95, blue: 0.80)
        case "orange": return Color(red: 1.00, green: 0.87, blue: 0.72)
        default:       return Color(red: 1.00, green: 0.95, blue: 0.60) // yellow
        }
    }

    /// Ink resolution: the near-black slot renders as the adaptive primary
    /// label color so strokes/text stay legible in dark mode; other slots
    /// are fixed hues that read on both appearances.
    static func inkColor(_ hex: String) -> Color {
        hex == inkColors[0] ? Color.primary : color(hex: hex)
    }

    /// "#RRGGBB" → Color; unparseable input falls back to primary label gray.
    static func color(hex: String) -> Color {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            return Color(nsColor: .labelColor)
        }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
