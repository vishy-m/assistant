import SwiftUI
import AssistantStore

/// Add or edit a task — title, optional due date, Low/Normal/High priority.
struct TaskEditorSheet: View {
    enum Mode { case add, edit(AssistantStore.Task) }

    let mode: Mode
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: Int

    init(mode: Mode, store: TaskStore) {
        self.mode = mode
        self._store = ObservedObject(wrappedValue: store)
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Date())
            _priority = State(initialValue: 1)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _hasDueDate = State(initialValue: task.dueAt != nil)
            _dueDate = State(initialValue: task.dueAt ?? Date())
            _priority = State(initialValue: task.priority)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing ? "Edit task" : "New task").font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            Toggle("Add due date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due", selection: $dueDate)
                    .datePickerStyle(.compact)
            }
            Picker("Priority", selection: $priority) {
                Text("Low").tag(0)
                Text("Normal").tag(1)
                Text("High").tag(2)
            }
            HStack {
                if case .edit(let task) = mode {
                    Button("Delete", role: .destructive) {
                        store.deleteTask(task)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let due = hasDueDate ? dueDate : nil
        switch mode {
        case .add:
            store.addTask(AssistantStore.Task(
                id: UUID().uuidString, title: trimmed, notes: nil, dueAt: due,
                completedAt: nil, courseId: nil, gradeItemId: nil,
                priority: priority, category: "Misc", source: "user"))
        case .edit(let existing):
            var updated = existing
            updated.title = trimmed
            updated.dueAt = due
            updated.priority = priority
            store.updateTask(updated)
        }
    }
}
