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
    /// The viewed class's board annotations, held locally as the live source of truth.
    @Published var annotations: [ClassAnnotationDTO] = []
    /// Unified board undo/redo (annotations + pins). Session-only, per class.
    @Published var boardHistory = BoardHistory()
    /// Board tool/session state (survives tab switches; reset on class switch).
    let board = BoardEditor()

    // MARK: - Syllabus scanning

    /// Files currently being scanned (spinner state).
    @Published var scanningFileIds: Set<String> = []
    /// A completed scan with proposals — presents the review sheet.
    @Published var syllabusScanResult: SyllabusScanResult?
    /// Human-readable notice for scans that produced nothing/failed.
    @Published var syllabusScanNotice: String?

    /// The class's root-level "Syllabus" folder, if the user hasn't deleted it.
    var rootSyllabusFolderId: String? {
        fileTree.folders.first {
            $0.folder.parentFolderId == nil
                && $0.folder.name.compare("syllabus", options: .caseInsensitive) == .orderedSame
        }?.id
    }

    func scanSyllabusFile(id: String) {
        guard !scanningFileIds.contains(id) else { return }
        scanningFileIds.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            guard let self, self.scanningFileIds.contains(id) else { return }
            self.scanningFileIds.remove(id)
            self.syllabusScanNotice = "Syllabus scan timed out. Right-click the file and choose Scan for Events to retry."
        }
        XPCClient.shared.scanSyllabusFile(fileId: id) { [weak self] result in
            guard let self, self.scanningFileIds.contains(id) else { return }
            self.scanningFileIds.remove(id)
            switch result.status {
            case .ok where !(result.events.isEmpty && result.tasks.isEmpty):
                self.syllabusScanResult = result
            case .ok, .nothingToScan:
                self.syllabusScanNotice = "No schedule information found in that file."
            case .llmUnavailable:
                self.syllabusScanNotice =
                    "No AI provider is configured. Add an API key in Settings to scan syllabi."
            case .failed(let message):
                self.syllabusScanNotice = "Syllabus scan failed: \(message)"
            }
        }
    }

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
    /// Resolves on-disk file URLs for previews. nil only if Application Support is unreachable.
    private let storage: ClassFileStorage? =
        (try? ClassFileStorage.defaultBase()).map { ClassFileStorage(base: $0) }
    private var changeObserver: NSObjectProtocol?
    private var pinObserver: NSObjectProtocol?
    private var filesObserver: NSObjectProtocol?
    private var annotationObserver: NSObjectProtocol?
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
        // Re-pull this class's annotations when another window edits the same class.
        annotationObserver = NotificationCenter.default.addObserver(
            forName: .assistantAnnotationsDidChange, object: nil, queue: .main) { [weak self] note in
            _Concurrency.Task { @MainActor in self?.reloadAnnotationsFromBroadcast(note) }
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
        if let annotationObserver { NotificationCenter.default.removeObserver(annotationObserver) }
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
        let isNewClass = courseId != currentCourseId
        currentCourseId = courseId
        restoreTabs(courseId: courseId)
        // Same-class refreshes (event/info saves re-call loadDetail) must not wipe the board session.
        if isNewClass {
            restoreViewport(courseId: courseId)
            focusedPinId = nil
        }
        detail = nil
        XPCClient.shared.getClassDetail(courseId: courseId) { [weak self] detail in
            self?.detail = detail
        }
        loadClassTasks(courseId: courseId)
        loadFiles(courseId: courseId)
        loadPins(courseId: courseId)
        if isNewClass {
            boardHistory = BoardHistory()
            board.reset()
        }
        loadAnnotations(courseId: courseId)
    }

    private func loadClassTasks(courseId: String) {
        XPCClient.shared.listTasks { [weak self] all in
            self?.classTasks = all.filter { $0.courseId == courseId }
        }
    }

    private func loadFiles(courseId: String) {
        XPCClient.shared.listClassFolders(courseId: courseId) { [weak self] folders in
            XPCClient.shared.listClassFiles(courseId: courseId) { [weak self] files in
                // Ignore a stale reply if the user has since switched classes —
                // otherwise we'd prune/persist this class's tabs under another.
                guard let self, self.currentCourseId == courseId else { return }
                self.fileTree = FileTreeBuilder.build(folders: folders, files: files)
                self.filesById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
                self.tabs.prune(toExisting: Set(files.map(\.id)))
                self.saveTabs()
            }
        }
    }

    private func loadPins(courseId: String) {
        XPCClient.shared.listClassPins(courseId: courseId) { [weak self] pins in
            self?.pins = pins
        }
    }

    private func loadAnnotations(courseId: String) {
        XPCClient.shared.listClassAnnotations(courseId: courseId) { [weak self] annotations in
            guard let self, self.currentCourseId == courseId else { return }
            self.annotations = annotations
        }
    }

    private func reloadFiles() {
        guard let courseId = currentCourseId else { return }
        loadFiles(courseId: courseId)
        loadPins(courseId: courseId)
    }

    /// After a local file/folder write: refresh our own tree (and pins), and on
    /// success tell other windows viewing this class to do the same.
    private func reloadAndBroadcastFiles(_ ok: Bool) {
        reloadFiles()
        if ok { broadcastFilesChanged() }
    }

    /// Tell other windows viewing this class to re-pull their file tree. Tagged
    /// with `self` so we skip our own echo (we already reloaded locally).
    private func broadcastFilesChanged() {
        guard let courseId = currentCourseId else { return }
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
        XPCClient.shared.createClassFolder(dto) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
    }

    func renameFolder(id: String, name: String) {
        XPCClient.shared.renameClassFolder(id: id, name: name) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
    }

    func moveFolder(id: String, toParent parentId: String?) {
        XPCClient.shared.moveClassFolder(id: id, parentId: parentId) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
    }

    func deleteFolder(id: String) {
        XPCClient.shared.deleteClassFolder(id: id) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
    }

    func renameFile(id: String, name: String) {
        XPCClient.shared.renameClassFile(id: id, name: name) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
    }

    func moveFile(id: String, toFolder folderId: String?) {
        XPCClient.shared.moveClassFile(id: id, folderId: folderId) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
    }

    func deleteFile(id: String) {
        XPCClient.shared.deleteClassFile(id: id) { [weak self] ok in self?.reloadAndBroadcastFiles(ok) }
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
        let isSyllabusDrop = dto.folderId != nil && dto.folderId == rootSyllabusFolderId
        XPCClient.shared.addClassFile(dto, bytes: bytes) { [weak self] ok in
            self?.reloadAndBroadcastFiles(ok)
            if ok && isSyllabusDrop { self?.scanSyllabusFile(id: dto.id) }
        }
    }

    // MARK: - Pins (local source of truth; write through to the daemon)

    func createPin(fileId: String, x: Double, y: Double, recordHistory: Bool = true) {
        guard let courseId = currentCourseId else { return }
        let pin = PinLayout.makePin(id: UUID().uuidString, courseId: courseId,
                                    fileId: fileId, x: x, y: y,
                                    zOrder: PinLayout.nextZOrder(pins))
        if recordHistory { boardHistory.record(.pin(before: nil, after: pin)) }
        pins.append(pin)
        XPCClient.shared.upsertClassPin(pin) { [weak self] ok in
            if ok { self?.broadcastPinsChanged() }
        }
    }

    /// Commit a moved/resized/rotated pin (called on gesture end). No-op if the
    /// pin is gone (e.g. a commit racing with its deletion), so we never recreate
    /// a ghost pin on the daemon.
    func updatePin(_ pin: ClassPinDTO, recordHistory: Bool = true) {
        guard let i = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        let before = pins.first { $0.id == pin.id }
        if recordHistory, let before, before != pin {
            boardHistory.record(.pin(before: before, after: pin))
        }
        pins[i] = pin
        XPCClient.shared.upsertClassPin(pin) { [weak self] ok in
            if ok { self?.broadcastPinsChanged() }
        }
    }

    func bringPinToFront(id: String) {
        guard let i = pins.firstIndex(where: { $0.id == id }) else { return }
        let raised = pins[i].withZOrder(PinLayout.nextZOrder(pins))
        pins[i] = raised
        XPCClient.shared.upsertClassPin(raised) { [weak self] ok in
            if ok { self?.broadcastPinsChanged() }
        }
    }

    /// Remove the placement only; the underlying file is untouched.
    func deletePin(id: String, recordHistory: Bool = true) {
        if recordHistory, let before = pins.first(where: { $0.id == id }) {
            boardHistory.record(.pin(before: before, after: nil))
        }
        pins.removeAll { $0.id == id }
        XPCClient.shared.deleteClassPin(id: id) { [weak self] ok in
            if ok { self?.broadcastPinsChanged() }
        }
    }

    /// On-disk URL of the file a pin points at, or nil if the file/storage is gone.
    func fileURL(for pin: ClassPinDTO) -> URL? {
        guard let file = filesById[pin.fileId], let storage else { return nil }
        return storage.fileURL(courseId: file.courseId, storedName: file.storedName)
    }

    /// Tell other windows viewing this class to re-pull pins. Tagged with `self`
    /// so we ignore our own echo (local pins are already updated optimistically).
    private func broadcastPinsChanged() {
        guard let courseId = currentCourseId else { return }
        NotificationCenter.default.post(name: .assistantPinsDidChange, object: self,
                                        userInfo: ["courseId": courseId])
    }

    /// Another window edited pins. Reload only if it was a different store and the
    /// change is for the class we're currently showing.
    private func reloadPinsFromBroadcast(_ note: Notification) {
        guard note.object as AnyObject !== self,
              let courseId = currentCourseId,
              note.userInfo?["courseId"] as? String == courseId else { return }
        loadPins(courseId: courseId)
    }

    // MARK: - Annotations (local source of truth; write through to the daemon)

    func nextAnnotationZOrder() -> Int {
        (annotations.map(\.zOrder).max() ?? -1) + 1
    }

    func createAnnotation(_ dto: ClassAnnotationDTO, recordHistory: Bool = true) {
        if recordHistory { boardHistory.record(.annotation(before: nil, after: dto)) }
        annotations.removeAll { $0.id == dto.id }
        annotations.append(dto)
        XPCClient.shared.upsertClassAnnotation(dto) { [weak self] ok in
            if ok { self?.broadcastAnnotationsChanged() }
        }
    }

    func updateAnnotation(_ dto: ClassAnnotationDTO, recordHistory: Bool = true) {
        // Never resurrect an annotation another window deleted mid-gesture
        // (mirrors updatePin's ghost guard). The undo executor routes absent
        // ids through createAnnotation, so undo/redo is unaffected.
        guard annotations.contains(where: { $0.id == dto.id }) else { return }
        let before = annotations.first { $0.id == dto.id }
        if recordHistory, let before, before != dto {
            boardHistory.record(.annotation(before: before, after: dto))
        }
        annotations.removeAll { $0.id == dto.id }
        annotations.append(dto)
        XPCClient.shared.upsertClassAnnotation(dto) { [weak self] ok in
            if ok { self?.broadcastAnnotationsChanged() }
        }
    }

    func deleteAnnotation(id: String, recordHistory: Bool = true) {
        guard let before = annotations.first(where: { $0.id == id }) else { return }
        if recordHistory { boardHistory.record(.annotation(before: before, after: nil)) }
        annotations.removeAll { $0.id == id }
        XPCClient.shared.deleteClassAnnotation(id: id) { [weak self] ok in
            if ok { self?.broadcastAnnotationsChanged() }
        }
    }

    /// Move a whole marquee selection as ONE undoable unit. Snapshots are
    /// taken first; writes then flow through the normal write-through paths
    /// with history recording disabled (the batch op carries the history).
    func moveSelection(annotationIds: Set<String>, pinIds: Set<String>,
                       dx: Double, dy: Double) {
        var ops: [BoardOp] = []
        for dto in annotations where annotationIds.contains(dto.id) {
            ops.append(.annotation(before: dto, after: movedAnnotation(dto, dx: dx, dy: dy)))
        }
        for pin in pins where pinIds.contains(pin.id) {
            ops.append(.pin(before: pin, after: pin.moved(x: pin.x + dx, y: pin.y + dy)))
        }
        guard !ops.isEmpty else { return }
        boardHistory.record(.batch(ops))
        for op in ops { apply(op, undo: false) }
    }

    /// Delete a whole marquee selection as ONE undoable unit.
    func deleteSelection(annotationIds: Set<String>, pinIds: Set<String>) {
        var ops: [BoardOp] = []
        for dto in annotations where annotationIds.contains(dto.id) {
            ops.append(.annotation(before: dto, after: nil))
        }
        for pin in pins where pinIds.contains(pin.id) {
            ops.append(.pin(before: pin, after: nil))
        }
        guard !ops.isEmpty else { return }
        boardHistory.record(.batch(ops))
        for op in ops { apply(op, undo: false) }
    }

    /// Translate an annotation, keeping stroke payload points in sync with
    /// the box (the stroke box/points contract).
    private func movedAnnotation(_ dto: ClassAnnotationDTO,
                                 dx: Double, dy: Double) -> ClassAnnotationDTO {
        var moved = dto.moved(x: dto.x + dx, y: dto.y + dy)
        if dto.annotationKind == .stroke,
           var payload = dto.decodedPayload(StrokePayload.self) {
            payload.points = AnnotationGeometry.translate(points: payload.points,
                                                          dx: dx, dy: dy)
            moved = moved.withPayload(ClassAnnotationDTO.encodePayload(payload))
        }
        return moved
    }

    private func broadcastAnnotationsChanged() {
        guard let courseId = currentCourseId else { return }
        NotificationCenter.default.post(name: .assistantAnnotationsDidChange, object: self,
                                        userInfo: ["courseId": courseId])
    }

    private func reloadAnnotationsFromBroadcast(_ note: Notification) {
        guard note.object as AnyObject !== self,
              let courseId = currentCourseId,
              note.userInfo?["courseId"] as? String == courseId else { return }
        loadAnnotations(courseId: courseId)
    }

    // MARK: - Unified board undo/redo

    func undoBoard() {
        guard let op = boardHistory.undo() else { return }
        apply(op, undo: true)
    }

    func redoBoard() {
        guard let op = boardHistory.redo() else { return }
        apply(op, undo: false)
    }

    /// Applies one side of an op WITHOUT recording history (recordHistory:
    /// false everywhere) — undo/redo must not generate new ops.
    private func apply(_ op: BoardOp, undo: Bool) {
        switch op {
        case .annotation(let before, let after):
            let target = undo ? before : after
            if let target {
                if annotations.contains(where: { $0.id == target.id }) {
                    updateAnnotation(target, recordHistory: false)
                } else {
                    createAnnotation(target, recordHistory: false)
                }
            } else if let victim = undo ? after : before {
                deleteAnnotation(id: victim.id, recordHistory: false)
            }
        case .pin(let before, let after):
            let target = undo ? before : after
            if let target {
                upsertPinForHistory(target)
            } else if let victim = undo ? after : before {
                deletePin(id: victim.id, recordHistory: false)
            }
        case .batch(let ops):
            // One history unit: undo replays members in reverse.
            for member in (undo ? Array(ops.reversed()) : ops) {
                apply(member, undo: undo)
            }
        }
    }

    /// Re-applies a pin snapshot through the same local-first + write-through
    /// path pins normally use (covers both "restore geometry" and "undelete").
    private func upsertPinForHistory(_ pin: ClassPinDTO) {
        pins.removeAll { $0.id == pin.id }
        pins.append(pin)
        XPCClient.shared.upsertClassPin(pin) { [weak self] ok in
            if ok { self?.broadcastPinsChanged() }
        }
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
