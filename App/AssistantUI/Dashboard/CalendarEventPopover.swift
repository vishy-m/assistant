import SwiftUI
import AssistantShared

struct CalendarEventPopover: View {
    enum Mode {
        case create(start: Date)
        case detail(WeekEvent)
    }

    let mode: Mode
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var durationMinutes: Int = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .create(let start):
                Text("New event").font(.headline)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                Picker("Duration", selection: $durationMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                    Text("2 hours").tag(120)
                }
                Text(rangeLabel(start, start.addingTimeInterval(Double(durationMinutes) * 60)))
                    .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Create") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
                        store.createEvent(title: t, start: start, end: end)
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
        .frame(width: 240)
    }

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d · h:mm a"
        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(t.string(from: end))"
    }
}
