import SwiftUI
import AssistantShared

/// Small popover shown when a task's deadline line on the calendar is tapped.
struct TaskDeadlinePopover: View {
    let task: WeekTask
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(.headline)
            Text(dueLabel)
                .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Mark complete") {
                    store.completeTask(task)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private var dueLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d · h:mm a"
        return "Due \(f.string(from: task.dueAt))"
    }
}
