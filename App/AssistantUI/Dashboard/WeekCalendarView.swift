import SwiftUI
import AssistantShared

struct WeekCalendarView: View {
    @ObservedObject var store: DashboardStore

    private let layout = WeekGridLayout(hourHeight: 44, dayStartHour: 0)
    private let visibleStartHour = 7
    private let cal = Calendar(identifier: .gregorian)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        hourGutter
                        ForEach(0..<7, id: \.self) { dayIndex in
                            dayColumn(dayIndex)
                        }
                    }
                    .id("grid")
                }
                .onAppear { proxy.scrollTo("hour-\(visibleStartHour)", anchor: .top) }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { store.shiftWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Button("Today") { store.goToToday() }
                .buttonStyle(.plain).foregroundStyle(GradeTheme.accent)
            Button { store.shiftWeek(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
            Spacer()
            Text(weekTitle).font(GradeTheme.metric(13))
        }
        .padding(10)
    }

    private var weekTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Week of \(f.string(from: store.weekStart))"
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(GradeTheme.mono(9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: layout.hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 4)
                    .id("hour-\(hour)")
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }

    private func dayColumn(_ dayIndex: Int) -> some View {
        let dayStart = cal.date(byAdding: .day, value: dayIndex, to: store.weekStart)!
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let dayEvents = store.events.filter { $0.startAt < dayEnd && $0.endAt > dayStart }
        let placements = WeekGridLayout.columns(for: dayEvents.map {
            WeekGridLayout.Interval(id: $0.id, start: $0.startAt, end: $0.endAt)
        })

        return VStack(spacing: 0) {
            Text(dayHeader(dayStart))
                .font(GradeTheme.mono(10))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Divider().frame(height: layout.hourHeight, alignment: .top)
                    }
                }
                ForEach(dayEvents) { event in
                    eventBlock(event, dayStart: dayStart,
                               placement: placements[event.id])
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(Divider(), alignment: .leading)
    }

    private func dayHeader(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }

    private func eventBlock(_ event: WeekEvent, dayStart: Date,
                            placement: WeekGridLayout.Placement?) -> some View {
        let top = layout.yOffset(for: max(event.startAt, dayStart), dayStart: dayStart)
        let height = layout.height(
            forDurationSeconds: event.endAt.timeIntervalSince(event.startAt))
        let count = placement?.columnCount ?? 1
        let index = placement?.columnIndex ?? 0
        return GeometryReader { geo in
            let colWidth = geo.size.width / CGFloat(count)
            CalendarEventBlock(event: event, store: store, layout: layout, dayStart: dayStart)
                .frame(width: colWidth, height: max(height, 16))
                .offset(x: colWidth * CGFloat(index), y: top)
        }
    }
}

private struct CalendarEventBlock: View {
    let event: WeekEvent
    let store: DashboardStore
    let layout: WeekGridLayout
    let dayStart: Date
    var body: some View {
        Text(event.title)
            .font(.caption2).lineLimit(1)
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GradeTheme.accent.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
