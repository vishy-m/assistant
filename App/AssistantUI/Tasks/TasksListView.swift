import SwiftUI
import AssistantStore

/// The rich Tasks UI — progress ring, sorted incomplete to-do list with
/// "+ Add", and a Completed section — extracted so it can render in both the
/// standalone Tasks window and the everything-dashboard's rail.
struct TasksListView: View {
    @ObservedObject var store: TaskStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            TaskProgressRing(fraction: store.progress,
                             completed: store.completedCount,
                             total: store.tasks.count)
                .padding(.vertical, 20)

            HStack {
                EyebrowLabel("To-do")
                Spacer()
                Button { showAdd = true } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(GradeTheme.accent)
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(incompleteTasks, id: \.id) { task in
                        TaskRow(task: task, store: store)
                    }
                    if incompleteTasks.isEmpty {
                        Text("Nothing to do")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    if !completedTasks.isEmpty {
                        completedSection
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showAdd) {
            TaskEditorSheet(mode: .add, onSave: { store.addTask($0) })
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel("Completed (\(completedTasks.count))")
                Spacer()
                Button("Clear completed") { store.clearCompleted() }
                    .font(.caption).buttonStyle(.plain)
                    .foregroundStyle(GradeTheme.accent)
            }
            .padding(.top, 14)
            ForEach(completedTasks, id: \.id) { task in
                TaskRow(task: task, store: store)
            }
        }
    }

    private var incompleteTasks: [AssistantStore.Task] {
        store.tasks.filter { $0.completedAt == nil }.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            switch (a.dueAt, b.dueAt) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.title < b.title
            }
        }
    }

    private var completedTasks: [AssistantStore.Task] {
        store.tasks.filter { $0.completedAt != nil }
    }
}
