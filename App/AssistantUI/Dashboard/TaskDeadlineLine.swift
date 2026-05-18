import SwiftUI
import AssistantShared

/// A task's deadline drawn on the week calendar — a thin, category-colored rule
/// with the task title. Drags vertically to reschedule the task; taps to open
/// the complete popover. The visible rule is thin but the view carries an
/// 18 pt hit area so it is easy to grab.
struct TaskDeadlineLine: View {
    let task: WeekTask
    @ObservedObject var store: DashboardStore
    let layout: WeekGridLayout

    @State private var dragOffset: CGFloat = 0
    @State private var showPopover = false

    var body: some View {
        let color = store.categoryColor(task.category)
        return VStack(alignment: .leading, spacing: 1) {
            Rectangle()
                .fill(color)
                .frame(height: 2)
            Text(task.title)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    let deltaSeconds = secondsFor(points: value.translation.height)
                    dragOffset = 0
                    guard deltaSeconds != 0 else { return }
                    store.rescheduleTask(
                        task, newDue: task.dueAt.addingTimeInterval(deltaSeconds))
                }
        )
        .onTapGesture { showPopover = true }
        .popover(isPresented: $showPopover) {
            TaskDeadlinePopover(task: task, store: store)
        }
    }

    /// Converts a point delta to a 15-minute-snapped second delta.
    private func secondsFor(points: CGFloat) -> TimeInterval {
        let rawSeconds = Double(points) / layout.hourHeight * 3600
        let snap = 15.0 * 60
        return (rawSeconds / snap).rounded() * snap
    }
}
