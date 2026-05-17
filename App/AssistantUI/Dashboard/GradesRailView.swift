import SwiftUI
import AssistantShared

struct GradesRailView: View {
    @ObservedObject var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                gpaSection
                Divider()
                classesSection
                Divider()
                recentSection
            }
            .padding(14)
        }
    }

    private var gpaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel("GPA")
            if store.gpaRevealed, let s = store.summary {
                Text(String(format: "%.2f", s.gpa))
                    .font(GradeTheme.metric(28))
                Text("\(s.gpaCountedCourses) of \(s.gpaTotalCourses) courses")
                    .font(GradeTheme.mono(10))
                    .foregroundStyle(.tertiary)
                Button("Hide") { store.gpaRevealed = false }
                    .font(.caption).buttonStyle(.plain)
                    .foregroundStyle(GradeTheme.accent)
            } else {
                Button("Reveal GPA") { store.gpaRevealed = true }
                    .font(.callout)
                    .buttonStyle(.plain)
                    .foregroundStyle(GradeTheme.accent)
            }
        }
    }

    private var classesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel("Classes")
            if let classes = store.summary?.classes, !classes.isEmpty {
                ForEach(classes) { c in
                    Button {
                        GradeDashboardWindow.shared.show()
                    } label: {
                        HStack {
                            Text(c.courseName).font(.callout).lineLimit(1)
                            Spacer()
                            Text("\(GradeTheme.num(c.currentPct))%  \(c.currentLetter)")
                                .font(GradeTheme.metric(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("No courses yet").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel("Recent grades")
            if let recent = store.summary?.recentGrades, !recent.isEmpty {
                ForEach(recent) { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(r.courseName) · \(r.itemName)")
                            .font(.caption).lineLimit(1)
                        Text("\(GradeTheme.num(r.earnedPct))% · \(relative(r.enteredAt))")
                            .font(GradeTheme.mono(10))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Nothing graded yet").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
