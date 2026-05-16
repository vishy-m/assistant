import SwiftUI
import AssistantStore

/// Create or edit a single grade item. The earned score and due date are
/// optional — an ungraded item still counts toward projections.
struct GradeItemEditorSheet: View {
    let courseId: String
    let categories: [GradeCategory]
    let existing: GradeItem?
    let onSave: (GradeItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var categoryId: String?
    @State private var maxPoints: Double
    @State private var hasEarned: Bool
    @State private var earnedPoints: Double
    @State private var isExtraCredit: Bool
    @State private var hasDue: Bool
    @State private var dueAt: Date

    init(courseId: String, categories: [GradeCategory], existing: GradeItem?,
         onSave: @escaping (GradeItem) -> Void) {
        self.courseId = courseId
        self.categories = categories
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _categoryId = State(initialValue: existing?.categoryId ?? categories.first?.id)
        _maxPoints = State(initialValue: existing?.maxPoints ?? 100)
        _hasEarned = State(initialValue: existing?.earnedPoints != nil)
        _earnedPoints = State(initialValue: existing?.earnedPoints ?? 0)
        _isExtraCredit = State(initialValue: existing?.isExtraCredit ?? false)
        _hasDue = State(initialValue: existing?.dueAt != nil)
        _dueAt = State(initialValue: existing?.dueAt ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(existing == nil ? "New grade item" : "Edit grade item")
                .font(.system(size: 15, weight: .semibold))

            field("Name") {
                TextField("Problem Set 1", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field("Category") {
                Picker("", selection: $categoryId) {
                    ForEach(categories, id: \.id) { cat in
                        Text(cat.name).tag(cat.id as String?)
                    }
                    Text("None (extra-credit pool)").tag(String?.none)
                }
                .labelsHidden()
            }

            HStack(spacing: 20) {
                field("Max points") {
                    TextField("", value: $maxPoints, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                        .multilineTextAlignment(.trailing)
                }
                field("Earned") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $hasEarned).labelsHidden()
                        TextField("", value: $earnedPoints, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 88)
                            .multilineTextAlignment(.trailing)
                            .disabled(!hasEarned)
                            .opacity(hasEarned ? 1 : 0.4)
                    }
                }
            }

            Toggle(isOn: $isExtraCredit) {
                Text("Extra credit — adds on top, never dropped")
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 5) {
                Toggle(isOn: $hasDue) {
                    Text("Has a due date").font(.system(size: 12))
                }
                if hasDue {
                    DatePicker("", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existing == nil ? "Add" : "Save") {
                    let item = GradeItem(
                        id: existing?.id ?? UUID().uuidString,
                        courseId: courseId,
                        categoryId: isExtraCredit ? categoryId : categoryId,
                        name: name,
                        maxPoints: maxPoints,
                        earnedPoints: hasEarned ? earnedPoints : nil,
                        dueAt: hasDue ? dueAt : nil,
                        isExtraCredit: isExtraCredit,
                        weightOverridePct: existing?.weightOverridePct)
                    XPCClient.shared.upsertItem(item) { _ in
                        onSave(item)
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
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
