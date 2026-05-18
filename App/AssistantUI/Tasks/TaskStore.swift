import Foundation
import SwiftUI
import AssistantStore

/// Owns the Tasks dashboard's data and is the only object that talks to the
/// daemon for it.
@MainActor
final class TaskStore: ObservableObject {

    @Published var tasks: [AssistantStore.Task] = []
    @Published var notesText: String = ""

    private var notesSaveTask: _Concurrency.Task<Void, Never>?

    func refresh() {
        XPCClient.shared.listTasks { [weak self] tasks in self?.tasks = tasks }
        XPCClient.shared.getTasksNote { [weak self] note in self?.notesText = note }
    }

    private func refreshTasks() {
        XPCClient.shared.listTasks { [weak self] tasks in self?.tasks = tasks }
    }

    var progress: Double { TaskProgress.fraction(tasks) }
    var completedCount: Int { tasks.filter { $0.completedAt != nil }.count }

    func addTask(_ task: AssistantStore.Task) {
        XPCClient.shared.createTask(task) { [weak self] _ in self?.refreshTasks() }
    }

    func updateTask(_ task: AssistantStore.Task) {
        XPCClient.shared.updateTask(task) { [weak self] _ in self?.refreshTasks() }
    }

    func deleteTask(_ task: AssistantStore.Task) {
        tasks.removeAll { $0.id == task.id }
        XPCClient.shared.deleteTask(taskId: task.id) { [weak self] ok in
            if !ok { self?.refreshTasks() }
        }
    }

    func toggleComplete(_ task: AssistantStore.Task) {
        let nowDone = task.completedAt == nil
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            var updated = tasks[idx]
            updated.completedAt = nowDone ? Date() : nil
            tasks[idx] = updated
        }
        XPCClient.shared.setTaskCompleted(taskId: task.id, completed: nowDone) { [weak self] ok in
            if !ok { self?.refreshTasks() }
        }
    }

    func clearCompleted() {
        tasks.removeAll { $0.completedAt != nil }
        XPCClient.shared.clearCompletedTasks { [weak self] _ in self?.refreshTasks() }
    }

    /// Updates the notes text immediately and saves on a short debounce.
    func saveNotes(_ text: String) {
        notesText = text
        notesSaveTask?.cancel()
        notesSaveTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            XPCClient.shared.setTasksNote(text) { _ in }
        }
    }
}
