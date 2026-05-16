import SwiftUI
import AssistantStore

/// Course rail on the left, course detail on the right. The rail is a calm
/// status surface — color-keyed courses, not a generic sidebar list.
struct GradeDashboardView: View {
    @ObservedObject var store: GradeStore
    @State private var showingNewCourse = false

    var body: some View {
        NavigationSplitView {
            courseRail
        } detail: {
            if store.selectedCourseId != nil {
                CourseDetailView(store: store)
            } else {
                emptyDetail
            }
        }
    }

    // MARK: - Rail

    private var courseRail: some View {
        List(selection: Binding(
            get: { store.selectedCourseId },
            set: { newID in
                store.selectedCourseId = newID
                if let id = newID { _Concurrency.Task { await store.selectCourse(id) } }
            }
        )) {
            Section {
                ForEach(store.courses, id: \.id) { course in
                    courseRow(course)
                        .tag(course.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                _Concurrency.Task { await store.deleteCourse(course.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                EyebrowLabel("Courses").padding(.bottom, 2)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 232)
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewCourse = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a course")
            }
        }
        .sheet(isPresented: $showingNewCourse) {
            NewCourseSheet { course in
                XPCClient.shared.upsertCourse(course) { _ in
                    _Concurrency.Task { await store.refreshCourses() }
                }
            }
        }
    }

    private func courseRow(_ course: Course) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(GradeTheme.color(fromHex: course.color))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(course.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let term = course.term, !term.isEmpty {
                    Text(term)
                        .font(GradeTheme.mono(10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if let target = course.targetGrade, !target.isEmpty {
                Text(target)
                    .font(GradeTheme.mono(10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(GradeTheme.hairline, lineWidth: 1))
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Empty detail

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.quaternary)
            Text("Select a course")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Grades, weighted breakdown, and projections appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GradeTheme.windowBg)
    }
}

// MARK: - New course sheet

struct NewCourseSheet: View {
    let onSave: (Course) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var term = ""
    @State private var targetGrade = "A-"
    @State private var colorHex = GradeTheme.coursePalette[0]

    private let letters = ["A", "A-", "B+", "B", "B-", "C+", "C"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New course")
                .font(.system(size: 15, weight: .semibold))

            field("Name") {
                TextField("Operating Systems", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            field("Term") {
                TextField("Fall 2026", text: $term)
                    .textFieldStyle(.roundedBorder)
            }
            field("Target grade") {
                Picker("", selection: $targetGrade) {
                    ForEach(letters, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 90)
            }
            field("Color") {
                HStack(spacing: 8) {
                    ForEach(GradeTheme.coursePalette, id: \.self) { hex in
                        Circle()
                            .fill(GradeTheme.color(fromHex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.55),
                                                lineWidth: hex == colorHex ? 2 : 0))
                            .onTapGesture { colorHex = hex }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add course") {
                    let course = Course(
                        id: UUID().uuidString, name: name, term: term.isEmpty ? nil : term,
                        color: colorHex, targetGrade: targetGrade,
                        gradingScaleJson: nil, syllabusSourcePath: nil)
                    onSave(course)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            EyebrowLabel(label)
            content()
        }
    }
}
