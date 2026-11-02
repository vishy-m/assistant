import SwiftUI
import AssistantStore

/// Create or edit a grade category. Labels above inputs; one primary action.
struct CategoryEditorSheet: View {
    let courseId: String
    let existing: GradeCategory?
    let onSave: (GradeCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var weightPct: Double
    @State private var dropLowest: Int
    @State private var dropHighest: Int
    @State private var saveError: String?

    init(courseId: String, existing: GradeCategory?,
         onSave: @escaping (GradeCategory) -> Void) {
        self.courseId = courseId
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _weightPct = State(initialValue: existing?.weightPct ?? 20)
        _dropLowest = State(initialValue: existing?.dropLowestN ?? 0)
        _dropHighest = State(initialValue: existing?.dropHighestN ?? 0)
        _saveError = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New category" : "Edit category")
                .font(.system(size: 15, weight: .semibold))

            field("Name") {
                TextField("Homework", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            field("Weight") {
                HStack(spacing: 6) {
                    TextField("", value: $weightPct, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                    Text("% of final grade")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 20) {
                field("Drop lowest") {
                    Stepper(value: $dropLowest, in: 0...10) {
                        Text("\(dropLowest)").font(GradeTheme.metric(13))
                    }
                }
                field("Drop highest") {
                    Stepper(value: $dropHighest, in: 0...10) {
                        Text("\(dropHighest)").font(GradeTheme.metric(13))
                    }
                }
            }

            if let message = visibleError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existing == nil ? "Add" : "Save") {
                    saveError = nil
                    guard canSave else { return }
                    let cat = GradeCategory(
                        id: existing?.id ?? UUID().uuidString,
                        courseId: courseId, name: name, weightPct: weightPct,
                        dropLowestN: dropLowest, dropHighestN: dropHighest)
                    XPCClient.shared.upsertCategory(cat) { ok in
                        guard ok else {
                            saveError = "Couldn't save this category."
                            return
                        }
                        onSave(cat)
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && GradeWriteRules.isSavableWeight(weightPct)
    }

    private var visibleError: String? {
        if let saveError { return saveError }
        if !trimmedName.isEmpty && !GradeWriteRules.isSavableWeight(weightPct) {
            return "Weight must be between 0 and 100."
        }
        return nil
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
