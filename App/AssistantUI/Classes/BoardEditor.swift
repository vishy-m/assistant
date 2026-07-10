import SwiftUI
import AssistantShared

/// Session state for the board's annotation tools: active tool, style
/// settings, selection, live (uncommitted) drawing, and drag state.
/// Owned by ClassStore so it survives tab switches; reset on class switch.
@MainActor
final class BoardEditor: ObservableObject {
    enum Tool: Equatable {
        case select, pen, eraser, sticky, text, shape
    }

    @Published var tool: Tool = .select
    @Published var shapeKind: AnnotationShape = .rect

    @Published var penColor: String = BoardStyle.inkColors[0]
    @Published var penWidth: Double = BoardStyle.penWidths[1]
    @Published var shapeStrokeColor: String = BoardStyle.inkColors[0]
    @Published var shapeFilled: Bool = false
    @Published var stickyColor: String = BoardStyle.stickySlots[0]
    @Published var textSize: Double = BoardStyle.textSizes[1].size
    @Published var textColor: String = BoardStyle.inkColors[0]

    /// Multi-select (marquee or click): annotations and pins that move and
    /// delete together. A plain click selects exactly one annotation.
    @Published var selectedAnnotationIds: Set<String> = []
    @Published var selectedPinIds: Set<String> = []
    @Published var editingAnnotationId: String?

    /// In-progress pen stroke, world points.
    @Published var liveStrokePoints: [[Double]] = []
    /// In-progress shape rubber-band, world points.
    @Published var liveShapeStart: CGPoint?
    @Published var liveShapeCurrent: CGPoint?
    /// Live translation of an ink annotation being dragged in select mode.
    @Published var inkDrag: (id: String, dx: Double, dy: Double)?
    /// Live marquee rubber-band, world points (select tool, drag from empty).
    @Published var marqueeStart: CGPoint?
    @Published var marqueeCurrent: CGPoint?
    /// Live world-space translation of the whole selection during a group drag.
    @Published var selectionDrag: CGSize?

    var isDrawingTool: Bool { tool == .pen || tool == .eraser || tool == .shape }
    var hasSelection: Bool { !selectedAnnotationIds.isEmpty || !selectedPinIds.isEmpty }
    var selectionCount: Int { selectedAnnotationIds.count + selectedPinIds.count }
    /// Non-nil when exactly one annotation (and no pins) is selected —
    /// single-selection affordances like the ink resize handle key off this.
    var soleSelectedAnnotationId: String? {
        selectedPinIds.isEmpty && selectedAnnotationIds.count == 1
            ? selectedAnnotationIds.first : nil
    }

    /// Class switch / board teardown: back to defaults that matter, keep the
    /// user's style choices (colors/widths persist within the session).
    func reset() {
        tool = .select
        selectedAnnotationIds = []
        selectedPinIds = []
        editingAnnotationId = nil
        liveStrokePoints = []
        liveShapeStart = nil
        liveShapeCurrent = nil
        inkDrag = nil
        marqueeStart = nil
        marqueeCurrent = nil
        selectionDrag = nil
    }
}
