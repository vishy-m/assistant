import SwiftUI
import AssistantShared
import AssistantStore

/// Review gate for syllabus scans: nothing is created until Create is pressed.
/// Rows are checked by default with editable titles and dates; recurring rows
/// show their pattern (recurrence itself is not editable in v1 — uncheck it
/// if it's wrong).
struct SyllabusReviewSheet: View {
    let result: SyllabusScanResult
    @ObservedObject var store: ClassStore
    @Environment(\.dismiss) private var dismiss

    struct EventRow: Identifiable {
        let id: String
        var included = true
        var title: String
        var startAt: Date
        let duration: TimeInterval
        let proposal: SyllabusProposedEvent
    }

    struct TaskRow: Identifiable {
        let id: String
        var included = true
        var title: String
        var dueAt: Date
        let proposal: SyllabusProposedTask
    }

    @State private var eventRows: [EventRow] = []
    @State private var taskRows: [TaskRow] = []
    @State private var creating = false

    private var includedCounts: (events: Int, tasks: Int) {
        (eventRows.filter(\.included).count, taskRows.filter(\.included).count)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Found in syllabus")
                .font(.headline)
                .padding()
            Divider()
            List {
                eventSection(.officeHours, header: "Office Hours")
                eventSection(.exam, header: "Exams")
                eventSection(.lecture, header: "Lectures")
                eventSection(.review, header: "Reviews")
                eventSection(.homeworkPattern, header: "Recurring Homework")
                if !taskRows.isEmpty {
                    Section("Deadlines (tasks)") {
                        ForEach($taskRows) { $row in
                            HStack {
                                Toggle("", isOn: $row.included).labelsHidden()
                                TextField("Title", text: $row.title)
                                DatePicker("", selection: $row.dueAt).labelsHidden()
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(creating
                       ? "Creating…"
                       : "Create \(includedCounts.events) events, \(includedCounts.tasks) tasks") {
                    createApproved()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(creating || (includedCounts.events + includedCounts.tasks == 0))
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { buildRows() }
    }

    @ViewBuilder
    private func eventSection(_ kind: SyllabusEventKind, header: String) -> some View {
        let indices = eventRows.indices.filter { eventRows[$0].proposal.kind == kind }
        if !indices.isEmpty {
            Section(header) {
                ForEach(indices, id: \.self) { i in
                    HStack {
                        Toggle("", isOn: $eventRows[i].included).labelsHidden()
                        TextField("Title", text: $eventRows[i].title)
                        DatePicker("", selection: $eventRows[i].startAt).labelsHidden()
                        if let rule = eventRows[i].proposal.recurrence {
                            Text(recurrenceSummary(rule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func buildRows() {
        eventRows = result.events.map {
            EventRow(id: $0.id, title: $0.title, startAt: $0.startAt,
                     duration: $0.endAt.timeIntervalSince($0.startAt), proposal: $0)
        }
        taskRows = result.tasks.map {
            TaskRow(id: $0.id, title: $0.title, dueAt: $0.dueAt, proposal: $0)
        }
    }

    private func recurrenceSummary(_ rule: RecurrenceRule) -> String {
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        let days = rule.byWeekday.sorted().compactMap { names[$0] }.joined(separator: ", ")
        var summary = "weekly on \(days)"
        if let until = rule.untilDate {
            summary += " until " + until.formatted(date: .abbreviated, time: .omitted)
        }
        return summary
    }

    /// Maps a proposal kind to an existing event type's id, when one matches.
    /// `CreateEventRequest.eventType` / `EventTypeDTO` are matched by id
    /// elsewhere in the app (e.g. `ClassEventCreatorSheet`, `DashboardStore.eventTypeColor`),
    /// so this must resolve to `.id`, not `.name`.
    private func eventType(for kind: SyllabusEventKind) -> String? {
        let wanted: String
        switch kind {
        case .officeHours: wanted = "Office Hours"
        case .exam: wanted = "Exam"
        case .lecture, .review: wanted = "Lecture"
        case .homeworkPattern: wanted = "Homework"
        }
        return store.eventTypes.first {
            $0.name.compare(wanted, options: .caseInsensitive) == .orderedSame
        }?.id
    }

    private func createApproved() {
        let courseId = result.courseId.isEmpty ? store.detail?.id : result.courseId
        guard let courseId, !courseId.isEmpty else { return }
        creating = true
        var failures = 0
        let group = DispatchGroup()
        for row in eventRows where row.included {
            group.enter()
            let request = CreateEventRequest(
                title: row.title,
                startAt: row.startAt,
                endAt: row.startAt.addingTimeInterval(row.duration),
                location: row.proposal.location,
                recurrence: row.proposal.recurrence,
                courseId: courseId,
                eventType: eventType(for: row.proposal.kind))
            XPCClient.shared.createCalendarEvent(request) { result in
                if result.errorMessage != nil || result.event == nil { failures += 1 }
                group.leave()
            }
        }
        for row in taskRows where row.included {
            group.enter()
            let task = AssistantStore.Task(
                id: UUID().uuidString, title: row.title, notes: row.proposal.notes,
                dueAt: row.dueAt, completedAt: nil, courseId: courseId,
                gradeItemId: nil, priority: 1, category: "Misc",
                source: "syllabus")
            XPCClient.shared.createTask(task) { ok in
                if !ok { failures += 1 }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            store.loadDetail(courseId: courseId) // refresh tasks/events views
            if failures > 0 {
                store.syllabusScanNotice =
                    "\(failures) item\(failures == 1 ? "" : "s") could not be created. Check your calendar connection and rescan to retry."
            }
            dismiss()
        }
    }
}
