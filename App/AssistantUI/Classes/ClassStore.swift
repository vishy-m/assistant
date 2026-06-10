import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AssistantShared
import AssistantStore

@MainActor
final class ClassStore: ObservableObject {
    @Published var classes: [ClassSummary] = []
    @Published var detail: ClassDetail?
    @Published var eventTypes: [EventTypeDTO] = []
    /// The viewed class's tasks (full records, for create/edit/complete).
    @Published var classTasks: [AssistantStore.Task] = []
    @Published var fileTree: FileTree = FileTree(folders: [], files: [])

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
        loadFiles(courseId: courseId)
    }

    private func loadClassTasks(courseId: String) {
        XPCClient.shared.listTasks { [weak self] all in
            self?.classTasks = all.filter { $0.courseId == courseId }
        }
    }

    private func loadFiles(courseId: String) {
        XPCClient.shared.listClassFolders(courseId: courseId) { [weak self] folders in
            XPCClient.shared.listClassFiles(courseId: courseId) { files in
                self?.fileTree = FileTreeBuilder.build(folders: folders, files: files)
            }
        }
    }

    private func reloadFiles() {
        guard let courseId = currentCourseId else { return }
        loadFiles(courseId: courseId)
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

    // MARK: - File/folder edits (reload the tree on completion)

    func createFolder(name: String, parentId: String?) {
        guard let courseId = currentCourseId else { return }
        let dto = ClassFolderDTO(id: UUID().uuidString, courseId: courseId,
                                 parentFolderId: parentId, name: name, sortOrder: 0)
        XPCClient.shared.createClassFolder(dto) { [weak self] _ in self?.reloadFiles() }
    }

    func renameFolder(id: String, name: String) {
        XPCClient.shared.renameClassFolder(id: id, name: name) { [weak self] _ in self?.reloadFiles() }
    }

    func moveFolder(id: String, toParent parentId: String?) {
        XPCClient.shared.moveClassFolder(id: id, parentId: parentId) { [weak self] _ in self?.reloadFiles() }
    }

    func deleteFolder(id: String) {
        XPCClient.shared.deleteClassFolder(id: id) { [weak self] _ in self?.reloadFiles() }
    }

    func renameFile(id: String, name: String) {
        XPCClient.shared.renameClassFile(id: id, name: name) { [weak self] _ in self?.reloadFiles() }
    }

    func moveFile(id: String, toFolder folderId: String?) {
        XPCClient.shared.moveClassFile(id: id, folderId: folderId) { [weak self] _ in self?.reloadFiles() }
    }

    func deleteFile(id: String) {
        XPCClient.shared.deleteClassFile(id: id) { [weak self] _ in self?.reloadFiles() }
    }

    /// Imports a file at `url` into `folderId` of the viewed class. Reads bytes,
    /// derives the content type + size, then sends both to the daemon.
    func importFile(at url: URL, folderId: String?) {
        guard let courseId = currentCourseId else { return }
        guard let bytes = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension
        let fileId = UUID().uuidString
        let storedName = ext.isEmpty ? fileId : "\(fileId).\(ext)"
        let uti = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier
            ?? UTType(filenameExtension: ext)?.identifier ?? "public.data"
        let dto = ClassFileDTO(id: fileId, courseId: courseId, folderId: folderId,
                               name: url.lastPathComponent, storedName: storedName,
                               contentType: uti, byteSize: bytes.count)
        XPCClient.shared.addClassFile(dto, bytes: bytes) { [weak self] _ in self?.reloadFiles() }
    }
}
