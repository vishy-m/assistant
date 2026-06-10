import SwiftUI
import AssistantShared

/// Bottom strip: this class's events for the current week, color-coded by type.
struct ClassMiniCalendar: View {
    @ObservedObject var store: ClassStore
    let events: [ClassEventItem]

    private let cal = Calendar(identifier: .gregorian)

    private var weekStart: Date {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? cal.startOfDay(for: Date())
    }

    private func typeColor(_ id: String?) -> Color {
        guard let id, let t = store.eventTypes.first(where: { $0.id == id }) else { return .secondary }
        return GradeTheme.color(fromHex: t.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowLabel("This week · events")
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    let dayStart = cal.date(byAdding: .day, value: i, to: weekStart)!
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
                    let dayEvents = events.filter { $0.startAt >= dayStart && $0.startAt < dayEnd }
                    VStack(spacing: 2) {
                        Text(Self.dayFmt.string(from: dayStart))
                            .font(GradeTheme.mono(8)).foregroundStyle(.tertiary)
                        ForEach(dayEvents) { ev in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(typeColor(ev.eventType))
                                .frame(height: 5)
                                .help(ev.title)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(3)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(10)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
}
