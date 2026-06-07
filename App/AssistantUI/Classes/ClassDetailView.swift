import SwiftUI
import AppKit
import AssistantShared

struct ClassDetailView: View {
    let courseId: String
    @ObservedObject var store: ClassStore
    @State private var showEditor = false

    var body: some View {
        Group {
            if let detail = store.detail, detail.id == courseId {
                content(detail)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(GradeTheme.windowBg)
        .onAppear { store.loadDetail(courseId: courseId) }
        .sheet(isPresented: $showEditor) {
            if let detail = store.detail {
                ClassInfoEditorSheet(detail: detail) { store.loadDetail(courseId: courseId) }
            }
        }
    }

    private func content(_ detail: ClassDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(detail)
                if !scheduleEvents(detail).isEmpty {
                    section("Schedule") {
                        ForEach(scheduleEvents(detail)) { eventRow($0) }
                    }
                }
                if !exams(detail).isEmpty {
                    section("Exams") {
                        ForEach(exams(detail)) { eventRow($0) }
                    }
                }
                if !detail.tasks.isEmpty {
                    section("Tasks & Deadlines") {
                        ForEach(detail.tasks) { taskRow($0) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(detail.name)
        .toolbar {
            ToolbarItemGroup {
                Button("Grades") { GradeDashboardWindow.shared.show() }
                Button("Edit") { showEditor = true }
            }
        }
    }

    // Schedule = recurring class-type sessions; exams shown separately.
    private func scheduleEvents(_ d: ClassDetail) -> [ClassEventItem] {
        d.events.filter { $0.eventType != "exam" }
    }
    private func exams(_ d: ClassDetail) -> [ClassEventItem] {
        d.events.filter { $0.eventType == "exam" }
    }

    private func header(_ d: ClassDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: d.iconName ?? "book.closed")
                    .foregroundStyle(GradeTheme.color(fromHex: d.colorHex))
                Text(d.name).font(GradeTheme.metric(20))
            }
            if let term = d.term, !term.isEmpty {
                Text(term).font(GradeTheme.mono(11)).foregroundStyle(.secondary)
            }
            if let prof = d.professorName, !prof.isEmpty {
                Text(prof).font(GradeTheme.mono(11))
            }
            if let email = d.professorEmail, !email.isEmpty {
                Button(email) {
                    if let url = URL(string: "mailto:\(email)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link).font(GradeTheme.mono(11))
            }
            if let room = d.classroom, !room.isEmpty {
                Label(room, systemImage: "mappin.and.ellipse")
                    .font(GradeTheme.mono(11)).foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(GradeTheme.mono(10)).foregroundStyle(.tertiary)
            content()
        }
    }

    private func eventRow(_ e: ClassEventItem) -> some View {
        HStack {
            Text(e.title).font(GradeTheme.mono(11))
            Spacer()
            Text(Self.dateFormatter.string(from: e.startAt))
                .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func taskRow(_ t: ClassTaskItem) -> some View {
        HStack {
            Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(t.isCompleted ? .green : .secondary)
            Text(t.title).font(GradeTheme.mono(11)).strikethrough(t.isCompleted)
            Spacer()
            if let due = t.dueAt {
                Text(Self.dateFormatter.string(from: due))
                    .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d, h:mm a"; return f
    }()
}
