import Foundation

/// One undoable board mutation, as before/after snapshots.
/// before == nil → the op created the object; after == nil → it deleted it.
/// Undo applies `before` (nil ⇒ delete), redo applies `after`.
public enum BoardOp: Equatable {
    case annotation(before: ClassAnnotationDTO?, after: ClassAnnotationDTO?)
    case pin(before: ClassPinDTO?, after: ClassPinDTO?)
}

/// Session-scoped unified undo/redo for the class board. Pure value type;
/// the store owns applying ops. Capped so marathon sessions don't hoard
/// stroke payloads forever.
public struct BoardHistory: Equatable {
    public static let cap = 100

    private var undoStack: [BoardOp] = []
    private var redoStack: [BoardOp] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Record a fresh user mutation. Any redo future is invalidated.
    public mutating func record(_ op: BoardOp) {
        undoStack.append(op)
        redoStack.removeAll()
        if undoStack.count > Self.cap { undoStack.removeFirst(undoStack.count - Self.cap) }
    }

    public mutating func undo() -> BoardOp? {
        guard let op = undoStack.popLast() else { return nil }
        redoStack.append(op)
        return op
    }

    public mutating func redo() -> BoardOp? {
        guard let op = redoStack.popLast() else { return nil }
        undoStack.append(op)
        return op
    }

    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
