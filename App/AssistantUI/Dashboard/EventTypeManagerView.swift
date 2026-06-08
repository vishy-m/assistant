import SwiftUI
import AssistantShared

struct EventTypeManagerView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event Types").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.eventTypes) { type in
                        EventTypeRow(store: store, type: type)
                    }
                }
            }
            Divider()
            HStack {
                TextField("New type", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty else { return }
                    store.saveEventType(EventTypeDTO(
                        id: UUID().uuidString, name: n, colorHex: "8A8F98",
                        symbolName: nil, isBuiltin: false))
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340, height: 420)
    }
}

private struct EventTypeRow: View {
    let store: DashboardStore
    let type: EventTypeDTO
    @State private var color: Color
    @State private var colorSaveTask: _Concurrency.Task<Void, Never>?

    init(store: DashboardStore, type: EventTypeDTO) {
        self.store = store
        self.type = type
        _color = State(initialValue: GradeTheme.color(fromHex: type.colorHex))
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
                        store.saveEventType(EventTypeDTO(
                            id: type.id, name: type.name, colorHex: hex,
                            symbolName: type.symbolName, isBuiltin: type.isBuiltin))
                    }
                }
            Text(type.name).font(GradeTheme.mono(11))
            Spacer()
            if type.isBuiltin {
                Text("built-in").font(GradeTheme.mono(9)).foregroundStyle(.tertiary)
            } else {
                Button(role: .destructive) {
                    store.deleteEventType(id: type.id)
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
