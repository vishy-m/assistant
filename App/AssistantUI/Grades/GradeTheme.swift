import SwiftUI
import AssistantGrades

/// Design tokens for the grade dashboard. One restrained accent, a tuned
/// surface ladder, and semantic colors used only to encode grade health —
/// never as decoration. Numbers carry the meaning, color only reinforces it.
enum GradeTheme {

    // MARK: Surfaces — adaptive, never pure black or flat white.

    static let windowBg = Color(nsColor: .underPageBackgroundColor)
    static let panelBg  = Color(nsColor: .controlBackgroundColor)
    static let railBg   = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color.primary.opacity(0.085)

    /// Single interactive accent — a muted slate, deliberately not the
    /// purple-blue AI default.
    static let accent = Color(red: 0.34, green: 0.40, blue: 0.52)

    // MARK: Semantic grade health.

    /// On-track / close / below, judged against the course's numeric target.
    static func health(pct: Double, target: Double) -> Color {
        if pct >= target      { return Color(red: 0.27, green: 0.52, blue: 0.36) }
        if pct >= target - 5  { return Color(red: 0.70, green: 0.52, blue: 0.18) }
        return Color(red: 0.71, green: 0.32, blue: 0.29)
    }

    // MARK: Typography — tabular figures for every metric.

    /// Rounded display figures with tabular spacing so columns of numbers align.
    static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Mono for IDs, weights, and structured metadata.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Helpers.

    /// Numeric cutoff for a target letter grade (defaults to 90 / "A-").
    static func targetCutoff(forLetter letter: String?) -> Double {
        guard let letter, let cut = GradingScale.default.minimum(forLetter: letter) else {
            return 90
        }
        return cut
    }

    /// Drops a trailing ".0" so whole numbers read cleanly.
    static func num(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(d))
            : String(format: "%.1f", d)
    }

    static func color(fromHex hex: String?) -> Color {
        var s = hex ?? "#7C8595"
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        return Color(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue:  Double(rgb & 0xFF) / 255)
    }

    /// Curated, calm course-color palette — no neon.
    static let coursePalette: [String] = [
        "#5C6B7A", "#4F7561", "#7A5C6B", "#7A6F4F",
        "#4F6B7A", "#6B5C7A", "#7A5C5C", "#5C7A6F"
    ]
}

/// An uppercase, tracked eyebrow label — the dashboard's section marker.
struct EyebrowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(GradeTheme.mono(10, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.tertiary)
    }
}
