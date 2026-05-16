import SwiftUI
import AssistantGrades

/// The inspector: the headline grade, a grade-scale ribbon for instant
/// placement, and a per-category contribution matrix.
struct BreakdownPanel: View {
    @ObservedObject var store: GradeStore

    private var targetCutoff: Double {
        let course = store.courses.first { $0.id == store.selectedCourseId }
        return GradeTheme.targetCutoff(forLetter: course?.targetGrade)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowLabel("Breakdown")
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if let b = store.breakdown {
                headline(b)
                scaleRibbon(current: b.currentPct, projected: b.projectedPct)
                Divider().padding(.horizontal, 18).padding(.vertical, 14)
                categoryMatrix(b)
                Spacer()
            } else {
                Spacer()
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(GradeTheme.panelBg)
    }

    // MARK: - Headline

    private func headline(_ b: GradeBreakdown) -> some View {
        let tone = GradeTheme.health(pct: b.currentPct, target: targetCutoff)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GradeTheme.num(b.currentPct))
                    .font(GradeTheme.metric(44, weight: .bold))
                    .foregroundStyle(tone)
                Text(b.currentLetter)
                    .font(GradeTheme.metric(22, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("Projected \(GradeTheme.num(b.projectedPct)) · \(b.projectedLetter)")
                    .font(GradeTheme.mono(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .animation(.snappy(duration: 0.25), value: b.currentPct)
    }

    // MARK: - Scale ribbon

    /// A thin band from F→A with a marker for current and a hairline for the
    /// target. Instant placement without a decorative chart.
    private func scaleRibbon(current: Double, projected: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamp: (Double) -> CGFloat = { CGFloat(min(max($0, 0), 100) / 100) * w }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [GradeTheme.health(pct: 50, target: targetCutoff),
                                 GradeTheme.health(pct: targetCutoff - 4, target: targetCutoff),
                                 GradeTheme.health(pct: 100, target: targetCutoff)],
                        startPoint: .leading, endPoint: .trailing))
                    .opacity(0.30)
                    .frame(height: 6)
                // target tick
                Rectangle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 1.5, height: 14)
                    .offset(x: clamp(targetCutoff) - 0.75)
                // projected marker (hollow)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
                    .background(Circle().fill(GradeTheme.panelBg))
                    .frame(width: 9, height: 9)
                    .offset(x: clamp(projected) - 4.5)
                // current marker (filled)
                Circle()
                    .fill(GradeTheme.health(pct: current, target: targetCutoff))
                    .frame(width: 11, height: 11)
                    .offset(x: clamp(current) - 5.5)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Category matrix

    private func categoryMatrix(_ b: GradeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowLabel("By category").padding(.horizontal, 18).padding(.bottom, 8)
            ForEach(b.perCategory, id: \.categoryId) { cat in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(cat.categoryName)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(GradeTheme.num(cat.currentPct))")
                            .font(GradeTheme.metric(12, weight: .semibold))
                        Text("· \(Int(cat.weightPct))%")
                            .font(GradeTheme.mono(10))
                            .foregroundStyle(.tertiary)
                    }
                    // contribution bar — width = weight, fill = current score
                    GeometryReader { geo in
                        let full = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(GradeTheme.hairline).frame(height: 4)
                            Capsule()
                                .fill(GradeTheme.health(pct: cat.currentPct, target: targetCutoff)
                                    .opacity(0.85))
                                .frame(width: full * CGFloat(min(cat.currentPct, 100) / 100),
                                       height: 4)
                        }
                    }
                    .frame(height: 4)
                    if !cat.droppedItemIds.isEmpty {
                        Text("\(cat.droppedItemIds.count) dropped")
                            .font(GradeTheme.mono(9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
    }
}
