import SwiftUI
import AssistantStore

struct CategoryManagerView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.categories, id: \.name) { category in
                        CategoryRow(store: store, category: category)
                    }
                }
            }
            Divider()
            HStack {
                TextField("New category", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty else { return }
                    store.saveCategory(originalName: nil, name: n, colorHex: "8A8F98")
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340, height: 420)
    }
}

private struct CategoryRow: View {
    let store: DashboardStore
    let category: AssistantStore.Category
    @State private var name: String
    @State private var color: Color
    @State private var colorSaveTask: _Concurrency.Task<Void, Never>?

    init(store: DashboardStore, category: AssistantStore.Category) {
        self.store = store
        self.category = category
        _name = State(initialValue: category.name)
        _color = State(initialValue: GradeTheme.color(fromHex: category.colorHex))
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { newColor in
                    colorSaveTask?.cancel()
                    let hex = hexString(newColor)
                    colorSaveTask = _Concurrency.Task { @MainActor in
                        try? await _Concurrency.Task.sleep(nanoseconds: 400_000_000)
                        guard !_Concurrency.Task.isCancelled else { return }
                        store.saveCategory(originalName: category.name, name: name,
                                           colorHex: hex)
                    }
                }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    store.saveCategory(originalName: category.name, name: name,
                                       colorHex: hexString(color))
                }
            if category.isDefault {
                Text("default").font(GradeTheme.mono(9)).foregroundStyle(.tertiary)
            } else {
                Button(role: .destructive) {
                    store.deleteCategory(name: category.name)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
            }
        }
    }

    private func hexString(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
