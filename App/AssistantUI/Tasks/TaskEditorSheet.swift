import SwiftUI
import AssistantStore

/// Add or edit a task — title, optional due date, Low/Normal/High priority.
/// Store-agnostic: the caller supplies `onSave`/`onDelete`. New tasks are
/// stamped with `defaultCourseId` (nil for the universal Tasks window, the
/// class's id when invoked from a class page) so class tasks auto-assign.
struct TaskEditorSheet: View {
    enum Mode { case add, edit(AssistantStore.Task) }

    let mode: Mode
    let defaultCourseId: String?
    let onSave: (AssistantStore.Task) -> Void
    let onDelete: ((AssistantStore.Task) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: Int

    init(mode: Mode, defaultCourseId: String? = nil,
         onSave: @escaping (AssistantStore.Task) -> Void,
         onDelete: ((AssistantStore.Task) -> Void)? = nil) {
        self.mode = mode
        self.defaultCourseId = defaultCourseId
        self.onSave = onSave
        self.onDelete = onDelete
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
                if case .edit(let task) = mode, let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete(task)
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
            onSave(AssistantStore.Task(
                id: UUID().uuidString, title: trimmed, notes: nil, dueAt: due,
                completedAt: nil, courseId: defaultCourseId, gradeItemId: nil,
                priority: priority, category: "Misc", source: "user"))
        case .edit(let existing):
            var updated = existing
            updated.title = trimmed
            updated.dueAt = due
            updated.priority = priority
            onSave(updated)
        }
    }
}
