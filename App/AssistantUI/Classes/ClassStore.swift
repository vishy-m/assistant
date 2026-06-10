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
    /// Flat lookup of the viewed class's files by id (name / content type / URL resolution).
    @Published var filesById: [String: ClassFileDTO] = [:]
    /// The viewed class's canvas pins, held locally as the live source of truth.
    @Published var pins: [ClassPinDTO] = []

    private var currentCourseId: String?
    /// Resolves on-disk file URLs for previews. nil only if Application Support is unreachable.
    private let storage: ClassFileStorage? =
        (try? ClassFileStorage.defaultBase()).map { ClassFileStorage(base: $0) }
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
        loadPins(courseId: courseId)
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
                self?.filesById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
            }
        }
    }

    private func loadPins(courseId: String) {
        XPCClient.shared.listClassPins(courseId: courseId) { [weak self] pins in
            self?.pins = pins
        }
    }

    private func reloadFiles() {
        guard let courseId = currentCourseId else { return }
        loadFiles(courseId: courseId)
        loadPins(courseId: courseId)
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

    // MARK: - Pins (local source of truth; write through to the daemon)

    func createPin(fileId: String, x: Double, y: Double) {
        guard let courseId = currentCourseId else { return }
        let pin = PinLayout.makePin(id: UUID().uuidString, courseId: courseId,
                                    fileId: fileId, x: x, y: y,
                                    zOrder: PinLayout.nextZOrder(pins))
        pins.append(pin)
        XPCClient.shared.upsertClassPin(pin) { _ in }
    }

    /// Commit a moved/resized/rotated pin (called on gesture end). No-op if the
    /// pin is gone (e.g. a commit racing with its deletion), so we never recreate
    /// a ghost pin on the daemon.
    func updatePin(_ pin: ClassPinDTO) {
        guard let i = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[i] = pin
        XPCClient.shared.upsertClassPin(pin) { _ in }
    }

    func bringPinToFront(id: String) {
        guard let i = pins.firstIndex(where: { $0.id == id }) else { return }
        let raised = pins[i].withZOrder(PinLayout.nextZOrder(pins))
        pins[i] = raised
        XPCClient.shared.upsertClassPin(raised) { _ in }
    }

    /// Remove the placement only; the underlying file is untouched.
    func deletePin(id: String) {
        pins.removeAll { $0.id == id }
        XPCClient.shared.deleteClassPin(id: id) { _ in }
    }

    /// On-disk URL of the file a pin points at, or nil if the file/storage is gone.
    func fileURL(for pin: ClassPinDTO) -> URL? {
        guard let file = filesById[pin.fileId], let storage else { return nil }
        return storage.fileURL(courseId: file.courseId, storedName: file.storedName)
    }
}

// Geometry-copy helpers — ClassPinDTO's fields are `let`, so mutations rebuild it.
// Internal (not private) so PinView in the same module reuses them.
extension ClassPinDTO {
    func moved(x: Double, y: Double) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: courseId, fileId: fileId, x: x, y: y,
                    width: width, height: height, rotation: rotation, zOrder: zOrder)
    }
    func resized(width: Double, height: Double) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: courseId, fileId: fileId, x: x, y: y,
                    width: width, height: height, rotation: rotation, zOrder: zOrder)
    }
    func rotated(_ rotation: Double) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: courseId, fileId: fileId, x: x, y: y,
                    width: width, height: height, rotation: rotation, zOrder: zOrder)
    }
    func withZOrder(_ zOrder: Int) -> ClassPinDTO {
        ClassPinDTO(id: id, courseId: courseId, fileId: fileId, x: x, y: y,
                    width: width, height: height, rotation: rotation, zOrder: zOrder)
    }
}
