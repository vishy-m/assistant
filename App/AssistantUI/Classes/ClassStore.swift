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
    /// Open file tabs + active tab for this class's canvas (persisted per course).
    @Published var tabs: CanvasTabs = CanvasTabs()
    /// The board's pan/zoom viewport for the viewed class (persisted per course).
    @Published var viewport = CanvasViewport()
    /// Live PDF previews on the board, for canvas-level scroll forwarding.
    let pdfViews = PDFViewRegistry()
    /// The pin the user last clicked, if any. A focused PDF pin captures
    /// two-finger scroll for reading; everything else pans the board.
    /// Session-only — never persisted.
    @Published var focusedPinId: String?

    private var currentCourseId: String?
    /// Tags each class load so replies for a previously selected class (or an
    /// older load of this one) are dropped instead of overwriting state.
    private var loadGate = ClassLoadGate()
    /// Resolves on-disk file URLs for previews. nil only if Application Support is unreachable.
    private let storage: ClassFileStorage? =
        (try? ClassFileStorage.defaultBase()).map { ClassFileStorage(base: $0) }
    private var changeObserver: NSObjectProtocol?
    private var pinObserver: NSObjectProtocol?
    private var filesObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init() {
        // Re-pull this class's tasks whenever any task changes anywhere.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .assistantTasksDidChange, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.reloadAfterTaskChange() }
        }
        // Re-pull this class's pins when another window edits the same class.
        pinObserver = NotificationCenter.default.addObserver(
            forName: .assistantPinsDidChange, object: nil, queue: .main) { [weak self] note in
            _Concurrency.Task { @MainActor in self?.reloadPinsFromBroadcast(note) }
        }
        // Re-pull this class's file tree when another window edits the same class.
        filesObserver = NotificationCenter.default.addObserver(
            forName: .assistantFilesDidChange, object: nil, queue: .main) { [weak self] note in
            _Concurrency.Task { @MainActor in self?.reloadFilesFromBroadcast(note) }
        }
        // Persist the board viewport on quit — gesture-end saves can miss the
        // final state (e.g. momentum still coasting when the app closes).
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveViewport() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        if let pinObserver { NotificationCenter.default.removeObserver(pinObserver) }
        if let filesObserver { NotificationCenter.default.removeObserver(filesObserver) }
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
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
        let token = loadGate.start(courseId: courseId)
        restoreTabs(courseId: courseId)
        restoreViewport(courseId: courseId)
        focusedPinId = nil
        // Clear the previous class's state so nothing of it stays actionable
        // (local only — nothing is deleted on the daemon).
        detail = nil
        classTasks = []
        pins = []
        filesById = [:]
        loadClassDetail(token)
        loadClassTasks(token)
        loadFiles(token)
        loadPins(token)
    }

    /// True if `token` is still the live load for the viewed class.
    private func accepts(_ token: ClassLoadGate.Token) -> Bool {
        loadGate.accepts(token) && currentCourseId == token.courseId
    }

    private func loadClassDetail(_ token: ClassLoadGate.Token) {
        XPCClient.shared.getClassDetail(courseId: token.courseId) { [weak self] detail in
            guard let self, self.accepts(token) else { return }
            self.detail = detail
        }
    }

    private func loadClassTasks(_ token: ClassLoadGate.Token) {
        XPCClient.shared.listTasks { [weak self] all in
            guard let self, self.accepts(token) else { return }
            self.classTasks = all.filter { $0.courseId == token.courseId }
        }
    }

    private func loadFiles(_ token: ClassLoadGate.Token) {
        let courseId = token.courseId
        XPCClient.shared.listClassFolders(courseId: courseId) { [weak self] folders in
            XPCClient.shared.listClassFiles(courseId: courseId) { [weak self] files in
                // Ignore a stale reply if the user has since switched classes —
                // otherwise we'd prune/persist this class's tabs under another.
                guard let self, self.accepts(token) else { return }
                self.fileTree = FileTreeBuilder.build(folders: folders, files: files)
                self.filesById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
                self.tabs.prune(toExisting: Set(files.map(\.id)))
                self.saveTabs()
            }
        }
    }

    private func loadPins(_ token: ClassLoadGate.Token) {
        XPCClient.shared.listClassPins(courseId: token.courseId) { [weak self] pins in
            guard let self, self.accepts(token) else { return }
            self.pins = pins
        }
    }

    private func reloadFiles() {
        guard let token = loadGate.current, currentCourseId == token.courseId else { return }
        loadFiles(token)
        loadPins(token)
    }

    /// After a local file/folder write: refresh our own tree (and pins), and on
    /// success tell other windows viewing `courseId` (captured when the write
    /// started) to do the same.
    private func reloadAndBroadcastFiles(_ ok: Bool, courseId: String?) {
        reloadFiles()
        if ok, let courseId { broadcastFilesChanged(courseId: courseId) }
    }

    /// Tell other windows viewing this class to re-pull their file tree. Tagged
    /// with `self` so we skip our own echo (we already reloaded locally).
    private func broadcastFilesChanged(courseId: String) {
        NotificationCenter.default.post(name: .assistantFilesDidChange, object: self,
                                        userInfo: ["courseId": courseId])
    }

    /// Another window edited this class's files. Reload only if it was a
    /// different store and the change is for the class we're currently showing.
    private func reloadFilesFromBroadcast(_ note: Notification) {
        guard note.object as AnyObject !== self,
              let courseId = currentCourseId,
              note.userInfo?["courseId"] as? String == courseId else { return }
        reloadFiles()
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
        guard let token = loadGate.current, currentCourseId == token.courseId else { return }
        loadClassTasks(token)
        loadClassDetail(token)
        refresh()  // keep the card grid's task counts current
    }

    // MARK: - File/folder edits (reload the tree on completion)

    func createFolder(name: String, parentId: String?) {
        guard let courseId = currentCourseId else { return }
        let dto = ClassFolderDTO(id: UUID().uuidString, courseId: courseId,
                                 parentFolderId: parentId, name: name, sortOrder: 0)
        XPCClient.shared.createClassFolder(dto) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: courseId) }
    }

    func renameFolder(id: String, name: String) {
        let cid = currentCourseId
        XPCClient.shared.renameClassFolder(id: id, name: name) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: cid) }
    }

    func moveFolder(id: String, toParent parentId: String?) {
        let cid = currentCourseId
        XPCClient.shared.moveClassFolder(id: id, parentId: parentId) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: cid) }
    }

    func deleteFolder(id: String) {
        let cid = currentCourseId
        XPCClient.shared.deleteClassFolder(id: id) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: cid) }
    }

    func renameFile(id: String, name: String) {
        let cid = currentCourseId
        XPCClient.shared.renameClassFile(id: id, name: name) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: cid) }
    }

    func moveFile(id: String, toFolder folderId: String?) {
        let cid = currentCourseId
        XPCClient.shared.moveClassFile(id: id, folderId: folderId) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: cid) }
    }

    func deleteFile(id: String) {
        let cid = currentCourseId
        XPCClient.shared.deleteClassFile(id: id) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: cid) }
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
        XPCClient.shared.addClassFile(dto, bytes: bytes) { [weak self] ok in self?.reloadAndBroadcastFiles(ok, courseId: courseId) }
    }

    // MARK: - Pins (local source of truth; write through to the daemon)

    func createPin(fileId: String, x: Double, y: Double) {
        guard let courseId = currentCourseId else { return }
        let pin = PinLayout.makePin(id: UUID().uuidString, courseId: courseId,
                                    fileId: fileId, x: x, y: y,
                                    zOrder: PinLayout.nextZOrder(pins))
        pins.append(pin)
        XPCClient.shared.upsertClassPin(pin) { [weak self] ok in
            if ok { self?.broadcastPinsChanged(courseId: pin.courseId) }
        }
    }

    /// Commit a moved/resized/rotated pin (called on gesture end). No-op if the
    /// pin is gone (e.g. a commit racing with its deletion), so we never recreate
    /// a ghost pin on the daemon.
    func updatePin(_ pin: ClassPinDTO) {
        guard let i = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[i] = pin
        XPCClient.shared.upsertClassPin(pin) { [weak self] ok in
            if ok { self?.broadcastPinsChanged(courseId: pin.courseId) }
        }
    }

    func bringPinToFront(id: String) {
        guard let i = pins.firstIndex(where: { $0.id == id }) else { return }
        let raised = pins[i].withZOrder(PinLayout.nextZOrder(pins))
        pins[i] = raised
        XPCClient.shared.upsertClassPin(raised) { [weak self] ok in
            if ok { self?.broadcastPinsChanged(courseId: raised.courseId) }
        }
    }

    /// Remove the placement only; the underlying file is untouched.
    func deletePin(id: String) {
        let courseId = currentCourseId
        pins.removeAll { $0.id == id }
        XPCClient.shared.deleteClassPin(id: id) { [weak self] ok in
            if ok, let courseId { self?.broadcastPinsChanged(courseId: courseId) }
        }
    }

    /// On-disk URL of the file a pin points at, or nil if the file/storage is gone.
    func fileURL(for pin: ClassPinDTO) -> URL? {
        guard let file = filesById[pin.fileId], let storage else { return nil }
        return storage.fileURL(courseId: file.courseId, storedName: file.storedName)
    }

    /// Tell other windows viewing this class to re-pull pins. Tagged with `self`
    /// so we ignore our own echo (local pins are already updated optimistically).
    private func broadcastPinsChanged(courseId: String) {
        NotificationCenter.default.post(name: .assistantPinsDidChange, object: self,
                                        userInfo: ["courseId": courseId])
    }

    /// Another window edited pins. Reload only if it was a different store and the
    /// change is for the class we're currently showing.
    private func reloadPinsFromBroadcast(_ note: Notification) {
        guard note.object as AnyObject !== self,
              let token = loadGate.current, currentCourseId == token.courseId,
              note.userInfo?["courseId"] as? String == token.courseId else { return }
        loadPins(token)
    }

    // MARK: - Canvas tabs (per-course, persisted in UserDefaults)

    func openFileTab(id: String) { tabs.open(id); saveTabs() }
    func closeFileTab(id: String) { tabs.close(id); saveTabs() }
    func selectFileTab(id: String) { tabs.selectFile(id); saveTabs() }
    func selectBoardTab() { tabs.selectBoard(); saveTabs() }

    private func tabsKey(_ courseId: String) -> String { "cf.\(courseId).tabs" }

    private func saveTabs() {
        guard let courseId = currentCourseId,
              let data = try? JSONEncoder().encode(tabs) else { return }
        UserDefaults.standard.set(data, forKey: tabsKey(courseId))
    }

    private func restoreTabs(courseId: String) {
        if let data = UserDefaults.standard.data(forKey: tabsKey(courseId)),
           let saved = try? JSONDecoder().decode(CanvasTabs.self, from: data) {
            tabs = saved
        } else {
            tabs = CanvasTabs()
        }
    }

    // MARK: - Canvas viewport (per-course, persisted in UserDefaults)

    private func viewportKey(_ courseId: String) -> String { "cf.\(courseId).viewport" }

    /// Called by the board on gesture end (not per-frame) to avoid write spam.
    func saveViewport() {
        guard let courseId = currentCourseId,
              let data = try? JSONEncoder().encode(viewport) else { return }
        UserDefaults.standard.set(data, forKey: viewportKey(courseId))
    }

    private func restoreViewport(courseId: String) {
        if let data = UserDefaults.standard.data(forKey: viewportKey(courseId)),
           let saved = try? JSONDecoder().decode(CanvasViewport.self, from: data) {
            viewport = saved
        } else {
            viewport = CanvasViewport()
        }
    }

    /// ⌘0: back to 100% zoom, centered on the pins (or the origin when the
    /// board is empty).
    func resetViewport(canvasSize: CGSize) {
        if let center = PinLayout.boundingCenter(of: pins) {
            viewport = .centered(onWorldX: center.x, worldY: center.y, canvasSize: canvasSize)
        } else {
            viewport = CanvasViewport()
        }
        saveViewport()
    }

    /// The viewed class's file by id (for tab titles / content type).
    func file(id: String) -> ClassFileDTO? { filesById[id] }

    /// On-disk URL of a file by id, or nil if the file/storage is gone.
    func fileURL(forFileId id: String) -> URL? {
        guard let file = filesById[id], let storage else { return nil }
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
