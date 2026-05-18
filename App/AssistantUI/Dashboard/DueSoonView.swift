import SwiftUI
import AssistantShared

struct DueSoonView: View {
    @ObservedObject var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowLabel("Due Soon")
                if let items = store.summary?.dueSoon, !items.isEmpty {
                    ForEach(items) { item in
                        row(item)
                    }
                } else {
                    Text("Nothing due in the next 7 days")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
        }
    }

    private func row(_ item: DueSoonItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(store.categoryColor(item.category))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout).lineLimit(2)
                HStack(spacing: 6) {
                    if let course = item.courseName {
                        Text(course).font(GradeTheme.mono(9)).foregroundStyle(.tertiary)
                    }
                    Text(dueLabel(item))
                        .font(GradeTheme.mono(9))
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }
            }
        }
    }

    private func dueLabel(_ item: DueSoonItem) -> String {
        if item.isOverdue { return "OVERDUE" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: item.dueAt, relativeTo: Date())
    }
}
