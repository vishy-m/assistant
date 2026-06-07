import SwiftUI
import AssistantShared

/// Creates a calendar event pre-scoped to a class. Lets the user pick the
/// event type, start time, duration, and recurrence, then writes it.
struct ClassEventCreatorSheet: View {
    let courseId: String
    @ObservedObject var store: ClassStore
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var eventType: String?
    @State private var start = Date()
    @State private var durationMinutes = 60
    @State private var repeats = false
    @State private var rule = RecurrenceRule(frequency: .weekly, interval: 1,
                                             byWeekday: [], untilDate: nil, count: nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Class Event").font(.headline)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $eventType) {
                Text("None").tag(String?.none)
                ForEach(store.eventTypes) { type in
                    Text(type.name).tag(String?.some(type.id))
                }
            }
            DatePicker("Start", selection: $start)
            Stepper("Duration: \(durationMinutes)m", value: $durationMinutes,
                    in: 15...480, step: 15)
            Toggle("Repeat", isOn: $repeats)
            if repeats { RecurrenceEditor(rule: $rule) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if eventType == nil { eventType = store.eventTypes.first?.id }
        }
    }

    private func create() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        let req = CreateEventRequest(title: t, startAt: start, endAt: end,
                                     location: nil, category: "Misc",
                                     recurrence: repeats ? rule : nil,
                                     courseId: courseId, eventType: eventType)
        XPCClient.shared.createCalendarEvent(req) { _ in
            onCreated()
            dismiss()
        }
    }
}
