import SwiftUI
import AssistantShared

/// Edits an existing class event: title, start, duration, type — plus Delete.
/// Recurrence is intentionally not editable here (add-flow only).
struct ClassEventEditorSheet: View {
    let courseId: String
    let event: ClassEventItem
    @ObservedObject var store: ClassStore
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var start: Date
    @State private var durationMinutes: Int
    @State private var eventType: String?

    init(courseId: String, event: ClassEventItem, store: ClassStore,
         onDone: @escaping () -> Void) {
        self.courseId = courseId
        self.event = event
        self.store = store
        self.onDone = onDone
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.startAt)
        _durationMinutes = State(initialValue: max(15,
            Int(event.endAt.timeIntervalSince(event.startAt) / 60)))
        _eventType = State(initialValue: event.eventType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Event").font(.headline)
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
            HStack {
                Button("Delete", role: .destructive) { deleteEvent() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        let req = UpdateEventRequest(eventId: event.id, startAt: start, endAt: end, title: t)
        XPCClient.shared.updateCalendarEvent(req) { _ in
            if eventType != event.eventType {
                XPCClient.shared.setEventClassification(
                    eventId: event.id, courseId: courseId, eventType: eventType) { _ in
                    finish()
                }
            } else {
                finish()
            }
        }
    }

    private func deleteEvent() {
        XPCClient.shared.deleteCalendarEvent(eventId: event.id) { _ in finish() }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}
