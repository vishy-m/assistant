import SwiftUI
import AssistantShared

/// Compact editor for a `RecurrenceRule`: frequency, interval, an optional
/// weekly day-of-week picker, and an end condition (never / on date / after N).
struct RecurrenceEditor: View {
    @Binding var rule: RecurrenceRule

    private enum EndKind: Hashable { case never, onDate, afterCount }

    // Calendar weekday ints (1 = Sun … 7 = Sat) with single-letter labels.
    private let weekdays: [(int: Int, label: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $rule.frequency) {
                    ForEach(RecurrenceRule.Frequency.allCases, id: \.self) { f in
                        Text(f.rawValue.capitalized).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Stepper("every \(rule.interval) \(unitLabel)",
                        value: $rule.interval, in: 1...99)
            }

            if rule.frequency == .weekly {
                HStack(spacing: 4) {
                    ForEach(weekdays, id: \.int) { day in
                        dayToggle(day.int, day.label)
                    }
                }
            }

            HStack(spacing: 8) {
                Picker("Ends", selection: endKindBinding) {
                    Text("Never").tag(EndKind.never)
                    Text("On date").tag(EndKind.onDate)
                    Text("After").tag(EndKind.afterCount)
                }
                .labelsHidden()
                .frame(width: 110)

                switch endKind {
                case .never:
                    EmptyView()
                case .onDate:
                    DatePicker("", selection: untilBinding, displayedComponents: [.date])
                        .labelsHidden()
                case .afterCount:
                    Stepper("\(rule.count ?? 1) times",
                            value: countBinding, in: 1...999)
                }
            }
        }
    }

    private var unitLabel: String {
        switch rule.frequency {
        case .daily: return rule.interval == 1 ? "day" : "days"
        case .weekly: return rule.interval == 1 ? "week" : "weeks"
        case .monthly: return rule.interval == 1 ? "month" : "months"
        case .yearly: return rule.interval == 1 ? "year" : "years"
        }
    }

    private func dayToggle(_ weekday: Int, _ label: String) -> some View {
        let on = rule.byWeekday.contains(weekday)
        return Button {
            if on { rule.byWeekday.removeAll { $0 == weekday } }
            else { rule.byWeekday.append(weekday) }
        } label: {
            Text(label)
                .font(.caption2)
                .frame(width: 20, height: 20)
                .background(on ? GradeTheme.accent : Color.secondary.opacity(0.15))
                .foregroundStyle(on ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - End-condition bindings

    private var endKind: EndKind {
        if rule.untilDate != nil { return .onDate }
        if rule.count != nil { return .afterCount }
        return .never
    }

    private var endKindBinding: Binding<EndKind> {
        Binding(get: { endKind }, set: { kind in
            switch kind {
            case .never:
                rule.untilDate = nil; rule.count = nil
            case .onDate:
                rule.count = nil
                if rule.untilDate == nil {
                    rule.untilDate = Calendar(identifier: .gregorian)
                        .date(byAdding: .month, value: 1, to: Date())
                }
            case .afterCount:
                rule.untilDate = nil
                if rule.count == nil { rule.count = 10 }
            }
        })
    }

    private var untilBinding: Binding<Date> {
        Binding(get: { rule.untilDate ?? Date() }, set: { rule.untilDate = $0 })
    }

    private var countBinding: Binding<Int> {
        Binding(get: { rule.count ?? 1 }, set: { rule.count = $0 })
    }
}
