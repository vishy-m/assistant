import Foundation

/// The class canvas's open-file tabs and which one is active. `activeFileId == nil`
/// means the permanent "Board" (pin board) tab is active. Pure value type so the
/// transitions are unit-tested off the UI; Codable so it persists as-is.
public struct CanvasTabs: Equatable, Codable {
    public private(set) var openFileIds: [String]
    public private(set) var activeFileId: String?

    public init(openFileIds: [String] = [], activeFileId: String? = nil) {
        self.openFileIds = openFileIds
        self.activeFileId = activeFileId
    }

    public var isBoardActive: Bool { activeFileId == nil }

    /// Open (or focus) a file tab and make it active.
    public mutating func open(_ id: String) {
        if !openFileIds.contains(id) { openFileIds.append(id) }
        activeFileId = id
    }

    /// Close a file tab. If it was active, fall back to the tab to its left, else
    /// the new tab at its position, else the Board.
    public mutating func close(_ id: String) {
        guard let idx = openFileIds.firstIndex(of: id) else { return }
        openFileIds.remove(at: idx)
        guard activeFileId == id else { return }
        if openFileIds.isEmpty {
            activeFileId = nil
        } else {
            let fallback = idx > 0 ? idx - 1 : 0
            activeFileId = openFileIds[min(fallback, openFileIds.count - 1)]
        }
    }

    public mutating func selectFile(_ id: String) {
        if openFileIds.contains(id) { activeFileId = id }
    }

    public mutating func selectBoard() { activeFileId = nil }

    /// Drop tabs whose file no longer exists; reset to Board if the active tab
    /// pointed at a removed file.
    public mutating func prune(toExisting existing: Set<String>) {
        openFileIds.removeAll { !existing.contains($0) }
        if let a = activeFileId, !existing.contains(a) { activeFileId = nil }
    }
}
