import SwiftUI
import AssistantShared

struct WeekCalendarView: View {
    @ObservedObject var store: DashboardStore

    private let layout = WeekGridLayout(hourHeight: 44, dayStartHour: 0)
    private let visibleStartHour = 7
    private let cal = Calendar(identifier: .gregorian)

    @State private var pendingCreateStart: Date?
    @State private var showCreate = false

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
                .popover(isPresented: $showCreate) {
                    if let start = pendingCreateStart {
                        CalendarEventPopover(mode: .create(start: start), store: store)
                    }
                }
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

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d"; return f
    }()

    private var weekTitle: String {
        return "Week of \(Self.monthDayFormatter.string(from: store.weekStart))"
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
                // Hour lines + click-to-create slots
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: layout.hourHeight)
                            .overlay(Divider(), alignment: .top)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                pendingCreateStart = cal.date(byAdding: .hour,
                                                              value: hour, to: dayStart)!
                                showCreate = true
                            }
                    }
                }
                ForEach(dayEvents) { event in
                    eventBlock(event, dayStart: dayStart, dayEnd: dayEnd,
                               placement: placements[event.id])
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(Divider(), alignment: .leading)
    }

    private func dayHeader(_ date: Date) -> String {
        return Self.dayHeaderFormatter.string(from: date)
    }

    private func eventBlock(_ event: WeekEvent, dayStart: Date, dayEnd: Date,
                            placement: WeekGridLayout.Placement?) -> some View {
        let clampedStart = max(event.startAt, dayStart)
        let clampedEnd = min(event.endAt, dayEnd)
        let top = layout.yOffset(for: clampedStart, dayStart: dayStart)
        let height = layout.height(
            forDurationSeconds: clampedEnd.timeIntervalSince(clampedStart))
        let count = placement?.columnCount ?? 1
        let index = placement?.columnIndex ?? 0
        return GeometryReader { geo in
            let colWidth = geo.size.width / CGFloat(count)
            CalendarEventBlock(event: event, store: store, layout: layout, dayStart: dayStart)
                .frame(width: colWidth, height: max(height, 28))
                .offset(x: colWidth * CGFloat(index), y: top)
        }
        .frame(height: CGFloat(24) * layout.hourHeight)
    }
}
