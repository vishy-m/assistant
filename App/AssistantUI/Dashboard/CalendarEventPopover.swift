import SwiftUI
import AssistantShared

struct CalendarEventPopover: View {
    enum Mode {
        case create(start: Date, end: Date)
        case detail(WeekEvent)
    }

    let mode: Mode
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var durationMinutes: Int
    @State private var category: String
    @State private var repeats = false
    @State private var rule = RecurrenceRule(frequency: .weekly, interval: 1,
                                             byWeekday: [], untilDate: nil, count: nil)

    init(mode: Mode, store: DashboardStore) {
        self.mode = mode
        self._store = ObservedObject(wrappedValue: store)
        switch mode {
        case .create(let start, let end):
            let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
            self._durationMinutes = State(initialValue: max(15, minutes))
        case .detail:
            self._durationMinutes = State(initialValue: 60)
        }
        switch mode {
        case .create:
            _category = State(initialValue:
                store.categories.first(where: { $0.isDefault })?.name ?? "Misc")
        case .detail(let event):
            _category = State(initialValue: event.category)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .create(let start, _):
                Text("New event").font(.headline)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                Stepper("Duration: \(durationLabel(durationMinutes))",
                        value: $durationMinutes, in: 15...480, step: 15)
                Text(rangeLabel(start, start.addingTimeInterval(Double(durationMinutes) * 60)))
                    .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
                Picker("Category", selection: $category) {
                    ForEach(store.categories, id: \.name) { c in
                        Text(c.name).tag(c.name)
                    }
                }
                Toggle("Repeat", isOn: $repeats)
                if repeats {
                    RecurrenceEditor(rule: $rule)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Create") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
                        store.createEvent(title: t, start: start, end: end,
                                          category: category,
                                          recurrence: repeats ? rule : nil)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            case .detail(let event):
                Text(event.title).font(.headline)
                Text(rangeLabel(event.startAt, event.endAt))
                    .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
                if let loc = event.location, !loc.isEmpty {
                    Text(loc).font(.caption)
                }
                Picker("Category", selection: $category) {
                    ForEach(store.categories, id: \.name) { c in
                        Text(c.name).tag(c.name)
                    }
                }
                .onChange(of: category) { newCategory in
                    store.setEventCategory(event, category: newCategory)
                }
                HStack {
                    Spacer()
                    Button("Delete", role: .destructive) {
                        store.deleteEvent(event)
                        dismiss()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func durationLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d · h:mm a"
        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(t.string(from: end))"
    }
}
