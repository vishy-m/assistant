import SwiftUI

/// Root view for the Tasks dashboard window: the rich Tasks list on the left,
/// a free-text notes panel on the right.
struct TasksDashboardView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        HStack(spacing: 0) {
            TasksListView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GradeTheme.panelBg)
            Divider()
            TasksNotesPanel(store: store)
                .frame(width: 280)
                .background(GradeTheme.railBg)
        }
        .background(GradeTheme.windowBg)
    }
}
