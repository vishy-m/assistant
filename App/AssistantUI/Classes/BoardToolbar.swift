import SwiftUI
import AssistantShared

/// FigJam-style floating tool palette (left edge) + undo/redo pill.
/// Clicking a tool activates it; clicking the active tool re-opens its
/// options popover (color/width/kind pickers).
struct BoardToolbar: View {
    @ObservedObject var store: ClassStore
    @ObservedObject var editor: BoardEditor

    @State private var penPopover = false
    @State private var shapePopover = false
    @State private var stickyPopover = false
    @State private var textPopover = false

    var body: some View {
        // Never taller than the board: prefer the full palette, fall back to
        // scrolling when the canvas is short. Contained content can't spill
        // over the tab bar / calendar / neighboring panels.
        ViewThatFits(in: .vertical) {
            stack
            ScrollView(.vertical, showsIndicators: false) { stack }
        }
        .padding(.leading, 12)
    }

    private var stack: some View {
        VStack(spacing: 10) {
            palette
            undoRedoPill
        }
    }

    private var palette: some View {
        VStack(spacing: 2) {
            toolButton(.select, icon: "cursorarrow", help: "Select")
            toolButton(.pen, icon: "scribble.variable", help: "Pen", popover: $penPopover) {
                penOptions
            }
            toolButton(.eraser, icon: "eraser", help: "Eraser")
            toolButton(.sticky, icon: "note.text", help: "Sticky note", popover: $stickyPopover) {
                stickyOptions
            }
            toolButton(.text, icon: "textformat", help: "Text", popover: $textPopover) {
                textOptions
            }
            toolButton(.shape, icon: "square.on.circle", help: "Shapes", popover: $shapePopover) {
                shapeOptions
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.1)))
    }

    private var undoRedoPill: some View {
        VStack(spacing: 2) {
            Button { store.undoBoard() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28)
            }
            .disabled(!store.boardHistory.canUndo || editor.editingAnnotationId != nil)
            .help("Undo (⌘Z)")
            Button { store.redoBoard() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 28, height: 28)
            }
            .disabled(!store.boardHistory.canRedo || editor.editingAnnotationId != nil)
            .help("Redo (⇧⌘Z)")
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.1)))
    }

    private func toolButton(_ tool: BoardEditor.Tool, icon: String, help: String) -> some View {
        Button {
            editor.tool = tool
            editor.editingAnnotationId = nil
        } label: {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .background(editor.tool == tool ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toolButton<Options: View>(
        _ tool: BoardEditor.Tool, icon: String, help: String,
        popover: Binding<Bool>, @ViewBuilder options: @escaping () -> Options
    ) -> some View {
        Button {
            if editor.tool == tool { popover.wrappedValue = true }
            editor.tool = tool
            editor.editingAnnotationId = nil
        } label: {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .background(editor.tool == tool ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(help) — click again for options")
        .popover(isPresented: popover, arrowEdge: .trailing) { options().padding(12) }
    }

    // MARK: option popovers

    private var penOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            colorRow(selection: $editor.penColor)
            HStack(spacing: 8) {
                ForEach(BoardStyle.penWidths, id: \.self) { width in
                    Button {
                        editor.penWidth = width
                    } label: {
                        Capsule().fill(Color.primary)
                            .frame(width: 28, height: width)
                            .padding(4)
                            .background(editor.penWidth == width
                                        ? Color.accentColor.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var shapeOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                shapeKindButton(.rect, icon: "rectangle")
                shapeKindButton(.ellipse, icon: "circle")
                shapeKindButton(.line, icon: "line.diagonal")
                shapeKindButton(.arrow, icon: "arrow.up.right")
            }
            colorRow(selection: $editor.shapeStrokeColor)
            Toggle("Fill", isOn: $editor.shapeFilled).toggleStyle(.checkbox)
        }
    }

    private var stickyOptions: some View {
        HStack(spacing: 8) {
            ForEach(BoardStyle.stickySlots, id: \.self) { slot in
                Button {
                    editor.stickyColor = slot
                } label: {
                    Circle().fill(BoardStyle.stickyColor(slot))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(
                            editor.stickyColor == slot ? Color.accentColor : .clear,
                            lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var textOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(BoardStyle.textSizes, id: \.name) { entry in
                    Button {
                        editor.textSize = entry.size
                    } label: {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(editor.textSize == entry.size
                                        ? Color.accentColor.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            colorRow(selection: $editor.textColor)
        }
    }

    private func shapeKindButton(_ kind: AnnotationShape, icon: String) -> some View {
        Button {
            editor.shapeKind = kind
        } label: {
            Image(systemName: icon)
                .frame(width: 26, height: 26)
                .background(editor.shapeKind == kind ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func colorRow(selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            ForEach(BoardStyle.inkColors, id: \.self) { hex in
                Button {
                    selection.wrappedValue = hex
                } label: {
                    Circle().fill(BoardStyle.color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(
                            selection.wrappedValue == hex ? Color.accentColor : .clear,
                            lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
