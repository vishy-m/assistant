import SwiftUI
import AssistantShared

struct ClassesDashboardView: View {
    @ObservedObject var store: ClassStore

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.classes.isEmpty {
                    Text("No classes yet. Add a course in Grades.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.classes) { summary in
                            NavigationLink(value: summary.id) {
                                ClassCard(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Classes")
            .navigationDestination(for: String.self) { courseId in
                ClassDetailView(courseId: courseId, store: store)
            }
        }
        .background(GradeTheme.windowBg)
        .onAppear { store.refresh() }
    }
}

private struct ClassCard: View {
    let summary: ClassSummary

    private var accent: Color {
        GradeTheme.color(fromHex: summary.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: summary.iconName ?? "book.closed")
                    .foregroundStyle(accent)
                Text(summary.name).font(GradeTheme.metric(15)).lineLimit(1)
                Spacer()
            }
            if let term = summary.term, !term.isEmpty {
                Text(term).font(GradeTheme.mono(10)).foregroundStyle(.secondary)
            }
            if let prof = summary.professorName, !prof.isEmpty {
                Text(prof).font(GradeTheme.mono(10)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let room = summary.classroom, !room.isEmpty {
                Text(room).font(GradeTheme.mono(10)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(summary.openTaskCount) tasks · \(summary.scheduleEventCount) sessions")
                .font(GradeTheme.mono(9)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(height: 110, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
