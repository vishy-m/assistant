import Foundation
import SwiftUI
import AssistantShared
import AssistantStore

@MainActor
final class ClassStore: ObservableObject {
    @Published var classes: [ClassSummary] = []
    @Published var detail: ClassDetail?
    @Published var eventTypes: [EventTypeDTO] = []
    /// The viewed class's tasks (full records, for create/edit/complete).
    @Published var classTasks: [AssistantStore.Task] = []

    private var currentCourseId: String?
    private var changeObserver: NSObjectProtocol?

    init() {
        // Re-pull this class's tasks whenever any task changes anywhere.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .assistantTasksDidChange, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.reloadAfterTaskChange() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    func refresh() {
        XPCClient.shared.listClasses { [weak self] classes in
            self?.classes = classes
        }
        XPCClient.shared.listEventTypes { [weak self] types in
            self?.eventTypes = types
        }
    }

    func loadDetail(courseId: String) {
        currentCourseId = courseId
        detail = nil
        XPCClient.shared.getClassDetail(courseId: courseId) { [weak self] detail in
            self?.detail = detail
        }
        loadClassTasks(courseId: courseId)
    }

    private func loadClassTasks(courseId: String) {
        XPCClient.shared.listTasks { [weak self] all in
            self?.classTasks = all.filter { $0.courseId == courseId }
        }
    }

    // MARK: - Task edits (auto-assigned to the viewed class)

    // Writes only; the `.assistantTasksDidChange` observer drives the reload
    // (so changes from other windows refresh this panel too).
    func addTask(_ task: AssistantStore.Task) {
        XPCClient.shared.createTask(task) { _ in }
    }

    func updateTask(_ task: AssistantStore.Task) {
        XPCClient.shared.updateTask(task) { _ in }
    }

    func deleteTask(_ task: AssistantStore.Task) {
        XPCClient.shared.deleteTask(taskId: task.id) { _ in }
    }

    func toggleTaskCompleted(_ task: AssistantStore.Task) {
        XPCClient.shared.setTaskCompleted(taskId: task.id, completed: task.completedAt == nil) { _ in }
    }

    /// Reload the class's tasks plus the detail/summary counts after a mutation.
    private func reloadAfterTaskChange() {
        guard let courseId = currentCourseId else { return }
        loadClassTasks(courseId: courseId)
        XPCClient.shared.getClassDetail(courseId: courseId) { [weak self] detail in
            self?.detail = detail
        }
        refresh()  // keep the card grid's task counts current
    }
}
