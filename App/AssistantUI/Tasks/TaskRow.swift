import SwiftUI
import AssistantStore

/// One to-do row: checkbox, priority dot, title, due date. Tap to edit;
/// swipe left to delete.
struct TaskRow: View {
    let task: AssistantStore.Task
    @ObservedObject var store: TaskStore

    @State private var showEditor = false

    var body: some View {
        SwipeToDelete(onDelete: { store.deleteTask(task) }) {
            rowContent
        }
    }

    private var rowContent: some View {
        let done = task.completedAt != nil
        return HStack(spacing: 8) {
            Button { store.toggleComplete(task) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? GradeTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            if task.priority >= 2 {
                Circle()
                    .fill(Color(red: 0.71, green: 0.32, blue: 0.29))
                    .frame(width: 6, height: 6)
            }

            Text(task.title)
                .font(.callout)
                .strikethrough(done)
                .foregroundStyle(done ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if let due = task.dueAt {
                Text(dueLabel(due))
                    .font(GradeTheme.mono(9))
                    .foregroundStyle(isOverdue(due) && !done ? .red : .secondary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { showEditor = true }
        .sheet(isPresented: $showEditor) {
            TaskEditorSheet(mode: .edit(task), store: store)
        }
    }

    private func isOverdue(_ due: Date) -> Bool { due < Date() }

    private static let dueFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
    }()

    private func dueLabel(_ date: Date) -> String {
        Self.dueFormatter.string(from: date)
    }
}
