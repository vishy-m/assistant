import Foundation

/// Grade figures for display. `Int(Double)` traps on NaN and on values outside
/// the integer range, so every conversion stays in string formatting.
public enum GradeFormat {
    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value.truncatingRemainder(dividingBy: 1) == 0,
           value >= Double(Int.min), value < Double(Int.max) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// Non-finite weights render as an em dash. Finite weights keep their percent sign.
    public static func weightPercent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(number(value))%"
    }
}
