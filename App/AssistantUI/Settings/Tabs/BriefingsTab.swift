import SwiftUI

struct BriefingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Daily briefings") {
                hmRow(label: "Morning",
                      h: $store.settings.morningBriefingHour,
                      m: $store.settings.morningBriefingMinute)
                hmRow(label: "Evening",
                      h: $store.settings.eveningBriefingHour,
                      m: $store.settings.eveningBriefingMinute)
            }
            Section("Pre-event lead times (minutes before start)") {
                leadRow(label: "Exam", binding: $store.settings.leadTimes.exam)
                leadRow(label: "Assignment due", binding: $store.settings.leadTimes.assignmentDue)
                leadRow(label: "Class", binding: $store.settings.leadTimes.classCategory)
                leadRow(label: "Club meeting", binding: $store.settings.leadTimes.clubMeeting)
                leadRow(label: "Internship deadline", binding: $store.settings.leadTimes.internshipDeadline)
                leadRow(label: "Generic event", binding: $store.settings.leadTimes.generic)
            }
            HStack {
                Spacer()
                Button("Save") { _Concurrency.Task { _ = await store.save() } }
                    .keyboardShortcut("s")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func hmRow(label: String, h: Binding<Int>, m: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(String(format: "%02d", h.wrappedValue)):\(String(format: "%02d", m.wrappedValue))",
                    onIncrement: { advance(h: h, m: m, by: 15) },
                    onDecrement: { advance(h: h, m: m, by: -15) })
                .fixedSize()
        }
    }

    private func advance(h: Binding<Int>, m: Binding<Int>, by minutes: Int) {
        var total = h.wrappedValue * 60 + m.wrappedValue + minutes
        total = max(0, min(23*60 + 59, total))
        h.wrappedValue = total / 60
        m.wrappedValue = total % 60
    }

    private func leadRow(label: String, binding: Binding<[Int]>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("comma-separated minutes",
                      text: Binding(
                        get: { binding.wrappedValue.map(String.init).joined(separator: ", ") },
                        set: { newVal in
                            binding.wrappedValue = newVal.split(separator: ",")
                                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        }))
                .frame(maxWidth: 220)
                .textFieldStyle(.roundedBorder)
        }
    }
}
