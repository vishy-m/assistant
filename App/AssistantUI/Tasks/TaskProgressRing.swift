import SwiftUI

/// A ring that fills with task-completion progress. Empty when there are no
/// tasks, full with a checkmark when everything is done.
struct TaskProgressRing: View {
    let fraction: Double          // 0...1
    let completed: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(GradeTheme.hairline, lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(GradeTheme.accent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: fraction)
            centerLabel
        }
        .frame(width: 120, height: 120)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if total == 0 {
            Text("No tasks")
                .font(GradeTheme.mono(10)).foregroundStyle(.tertiary)
        } else if completed == total {
            Image(systemName: "checkmark")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(GradeTheme.accent)
        } else {
            VStack(spacing: 1) {
                Text("\(completed) of \(total)").font(GradeTheme.metric(18))
                Text("done").font(GradeTheme.mono(9)).foregroundStyle(.tertiary)
            }
        }
    }
}
