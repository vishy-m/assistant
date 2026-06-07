import SwiftUI
import AssistantShared
import AssistantStore

/// Edits a class's identity/contact fields. Loads the full Course (to preserve
/// grade-related fields), applies edits, and upserts.
struct ClassInfoEditorSheet: View {
    let detail: ClassDetail
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var term: String = ""
    @State private var professorName: String = ""
    @State private var professorEmail: String = ""
    @State private var classroom: String = ""
    @State private var colorHex: String = ""
    @State private var iconName: String = ""
    @State private var base: Course?

    private let iconChoices = ["book.closed", "function", "atom", "flask",
                               "laptopcomputer", "paintbrush", "globe", "music.note"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Class").font(GradeTheme.metric(16))
            Form {
                TextField("Name", text: $name)
                TextField("Term", text: $term)
                TextField("Professor", text: $professorName)
                TextField("Email", text: $professorEmail)
                TextField("Classroom", text: $classroom)
                TextField("Color hex (e.g. 4F6B7A)", text: $colorHex)
                Picker("Icon", selection: $iconName) {
                    ForEach(iconChoices, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private func load() {
        name = detail.name
        term = detail.term ?? ""
        professorName = detail.professorName ?? ""
        professorEmail = detail.professorEmail ?? ""
        classroom = detail.classroom ?? ""
        colorHex = detail.colorHex ?? ""
        iconName = detail.iconName ?? "book.closed"
        XPCClient.shared.listCourses { courses in
            base = courses.first { $0.id == detail.id }
        }
    }

    private func save() {
        guard var course = base else { dismiss(); return }
        course.name = name
        course.term = term.isEmpty ? nil : term
        course.professorName = professorName.isEmpty ? nil : professorName
        course.professorEmail = professorEmail.isEmpty ? nil : professorEmail
        course.classroom = classroom.isEmpty ? nil : classroom
        course.color = colorHex.isEmpty ? nil : colorHex
        course.iconName = iconName
        XPCClient.shared.upsertCourse(course) { _ in
            onSave()
            dismiss()
        }
    }
}
