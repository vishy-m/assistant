import SwiftUI
import AssistantShared

/// A sticky note or text box on the board: world-space SwiftUI view (same
/// coordinate story as pins, rendered below them). Select-mode interactions:
/// tap selects, drag moves, corner handle resizes, double-click edits text,
/// context menu removes. An object left with empty text deletes itself.
struct BoardObjectView: View {
    let dto: ClassAnnotationDTO
    @ObservedObject var store: ClassStore
    @ObservedObject var editor: BoardEditor

    @State private var dragOffset: CGSize = .zero
    @State private var liveSize: CGSize?
    @State private var draft: String = ""
    @FocusState private var textFocused: Bool

    private var isSelected: Bool { editor.selectedAnnotationIds.contains(dto.id) }
    /// Offset applied while the whole selection is being dragged from any member.
    private var groupOffset: CGSize {
        (isSelected && editor.selectionCount > 1) ? (editor.selectionDrag ?? .zero) : .zero
    }
    private var isEditing: Bool { editor.editingAnnotationId == dto.id }
    private var size: CGSize { liveSize ?? CGSize(width: dto.width, height: dto.height) }

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) { if isSelected { resizeHandle } }
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .onTapGesture(count: 2) { beginEditing() }
            .onTapGesture {
                editor.selectedAnnotationIds = [dto.id]
                editor.selectedPinIds = []
                // Tapping one object ends any other object's edit session.
                if editor.editingAnnotationId != dto.id { editor.editingAnnotationId = nil }
            }
            .contextMenu {
                Button("Edit Text") { beginEditing() }
                Button("Remove", role: .destructive) {
                    editor.selectedAnnotationIds.remove(dto.id)
                    store.deleteAnnotation(id: dto.id)
                }
            }
            .position(x: dto.x + dragOffset.width + groupOffset.width,
                      y: dto.y + dragOffset.height + groupOffset.height)
            .onChange(of: isEditing) { _ in if !isEditing { endEditing() } }
    }

    @ViewBuilder private var content: some View {
        switch dto.annotationKind {
        case .sticky:
            let payload = dto.decodedPayload(StickyPayload.self)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(BoardStyle.stickyColor(payload?.color ?? "yellow"))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                textBody(payload?.text ?? "", font: .system(size: 14, weight: .medium),
                         color: Color.black.opacity(0.8))
                    .padding(10)
            }
        case .text:
            let payload = dto.decodedPayload(TextPayload.self)
            textBody(payload?.text ?? "",
                     font: .system(size: payload?.fontSize ?? 20),
                     color: BoardStyle.inkColor(payload?.color ?? "#1D1D1F"))
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func textBody(_ text: String, font: Font, color: Color) -> some View {
        if isEditing {
            TextEditor(text: $draft)
                .font(font)
                .foregroundStyle(color)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($textFocused)
                .onAppear { draft = text; textFocused = true }
                .onChange(of: textFocused) { _ in
                    // Focus steal (clicking a pin, another window, any other
                    // text field) ends editing; onChange(of: isEditing) then
                    // commits or self-deletes via endEditing().
                    if !textFocused && isEditing { editor.editingAnnotationId = nil }
                }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func beginEditing() {
        editor.selectedAnnotationIds = [dto.id]
        editor.selectedPinIds = []
        editor.editingAnnotationId = dto.id
    }

    /// Commit or self-delete on edit end.
    private func endEditing() {
        textFocused = false
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch dto.annotationKind {
        case .sticky:
            guard var payload = dto.decodedPayload(StickyPayload.self) else { return }
            if text.isEmpty {
                editor.selectedAnnotationIds.remove(dto.id)
                store.deleteAnnotation(id: dto.id)
                return
            }
            payload.text = draft
            store.updateAnnotation(dto.withPayload(ClassAnnotationDTO.encodePayload(payload)))
        case .text:
            guard var payload = dto.decodedPayload(TextPayload.self) else { return }
            if text.isEmpty {
                editor.selectedAnnotationIds.remove(dto.id)
                store.deleteAnnotation(id: dto.id)
                return
            }
            payload.text = draft
            store.updateAnnotation(dto.withPayload(ClassAnnotationDTO.encodePayload(payload)))
        default: break
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard !isEditing else { return }
                // Dragging any member of a multi-selection moves the whole
                // selection live; the store commits one batch op on release.
                if isSelected && editor.selectionCount > 1 {
                    editor.selectionDrag = value.translation
                    return
                }
                if dragOffset == .zero {
                    editor.selectedAnnotationIds = [dto.id]
                    editor.selectedPinIds = []
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isEditing else { return }
                if isSelected && editor.selectionCount > 1, editor.selectionDrag != nil {
                    editor.selectionDrag = nil
                    store.moveSelection(annotationIds: editor.selectedAnnotationIds,
                                        pinIds: editor.selectedPinIds,
                                        dx: value.translation.width,
                                        dy: value.translation.height)
                    return
                }
                dragOffset = .zero
                store.updateAnnotation(dto.moved(x: dto.x + value.translation.width,
                                                 y: dto.y + value.translation.height))
            }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .offset(x: 5, y: 5)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        liveSize = CGSize(width: max(60, dto.width + value.translation.width),
                                          height: max(32, dto.height + value.translation.height))
                    }
                    .onEnded { _ in
                        if let s = liveSize {
                            store.updateAnnotation(dto.resized(width: s.width, height: s.height))
                        }
                        liveSize = nil
                    }
            )
    }
}
