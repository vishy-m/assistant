import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @StateObject private var taskStore = TaskStore()

    var body: some View {
        HStack(spacing: 0) {
            // Left rail: grades + tasks stacked.
            VStack(spacing: 0) {
                GradesRailView(store: store)
                Divider()
                TasksListView(store: taskStore)
            }
            .frame(width: 220)
            .background(GradeTheme.railBg)

            Divider()

            // Center: week calendar.
            WeekCalendarView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GradeTheme.panelBg)

            Divider()

            // Right: chat.
            DashboardChatView(store: store)
                .frame(width: 320)
                .background(GradeTheme.railBg)
        }
        .background(GradeTheme.windowBg)
        .onAppear { taskStore.refresh() }
    }
}
