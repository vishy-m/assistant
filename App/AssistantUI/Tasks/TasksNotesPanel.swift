import SwiftUI

/// Free-text notes scratchpad for the Tasks dashboard. Autosaves via the store.
struct TasksNotesPanel: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel("Notes")
            TextEditor(text: Binding(
                get: { store.notesText },
                set: { store.saveNotes($0) }))
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(GradeTheme.panelBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
    }
}
