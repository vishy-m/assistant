import SwiftUI
import AssistantShared

/// A week time-grid of this class's events, colored by event type. Reuses
/// WeekGridLayout for geometry. Renders only the hour window that contains the
/// week's events (plus an hour of padding) so events are laid out visible
/// without any scroll-position juggling. Tapping an event calls `onSelectEvent`.
struct ClassWeekCalendar: View {
    @ObservedObject var store: ClassStore
    let events: [ClassEventItem]
    var onSelectEvent: (ClassEventItem) -> Void

    @State private var weekStart: Date = ClassWeekCalendar.startOfWeek(Date())

    private let cal = Calendar(identifier: .gregorian)
    private let hourHeight: Double = 40
    private let gutter: CGFloat = 34

    private var layout: WeekGridLayout {
        WeekGridLayout(hourHeight: hourHeight, dayStartHour: displayRange.start)
    }

    /// The hour window [start, end) to render: tight around the week's events
    /// (with an hour of padding above and below), defaulting to 8am–8pm when
    /// there are none. Because the grid *starts* at `start`, events are visible
    /// immediately — no auto-scroll, which the shared store's frequent
    /// re-publishes during load would otherwise clobber.
    private var displayRange: (start: Int, end: Int) {
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let weekEvents = events.filter { $0.startAt >= weekStart && $0.startAt < weekEnd }
        guard !weekEvents.isEmpty else { return (8, 20) }
        let startHour = weekEvents.map { ev in
            WeekGridLayout.wallHour(of: ev.startAt, calendar: cal)
        }.min() ?? 8
        let endHour = weekEvents.map { ev -> Int in
            WeekGridLayout.exclusiveEndHour(
                of: ev.endAt, dayStart: cal.startOfDay(for: ev.startAt), calendar: cal)
        }.max() ?? 20
        let start = max(0, startHour - 1)
        let end = min(24, max(endHour + 1, start + 4))
        return (start, end)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let colW = max((geo.size.width - gutter) / 7, 1)
                VStack(spacing: 0) {
                    dayLabels(colW: colW)
                    Divider()
                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            hourRows(colW: colW)
                            blocks(colW: colW)
                        }
                        .clipped()
                    }
                }
            }
        }
        .padding(8)
    }

    // MARK: Header / day labels

    private var header: some View {
        HStack(spacing: 10) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Button("Today") { weekStart = Self.startOfWeek(Date()) }
                .buttonStyle(.plain).foregroundStyle(GradeTheme.accent)
            Button { shift(7) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
            Text(weekRangeLabel).font(GradeTheme.mono(11)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func dayLabels(colW: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: weekStart)!
                Text(Self.dayFmt.string(from: day))
                    .font(GradeTheme.mono(9))
                    .foregroundStyle(cal.isDateInToday(day) ? GradeTheme.accent : .secondary)
                    .frame(width: colW, alignment: .center)
            }
        }
        // Constrain the row height — `Color.clear` and the day Texts have no
        // intrinsic height and would otherwise expand to fill the panel,
        // pushing the grid far down with a big empty band above it.
        .frame(height: 16)
        .padding(.vertical, 2)
    }

    // MARK: Grid + blocks

    /// Laid-out hour rows for the display window (each `hourHeight` tall). The
    /// separator sits at each row's top, matching block yOffsets, and the
    /// stack's height defines the scroll content.
    private func hourRows(colW: CGFloat) -> some View {
        let range = displayRange
        return VStack(spacing: 0) {
            ForEach(range.start..<range.end, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 1)
                        .padding(.leading, gutter)
                    Text(String(format: "%02d:00", hour))
                        .font(GradeTheme.mono(8)).foregroundStyle(.secondary)
                        .frame(width: gutter - 4, alignment: .trailing)
                        .offset(y: -5)
                }
                .frame(maxWidth: .infinity, minHeight: CGFloat(hourHeight),
                       maxHeight: CGFloat(hourHeight), alignment: .topLeading)
            }
        }
    }

    private func blocks(colW: CGFloat) -> some View {
        ForEach(placedBlocks(colW: colW)) { b in
            RoundedRectangle(cornerRadius: 4)
                .fill(b.color.opacity(0.85))
                .frame(width: b.width, height: b.height)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.title).font(GradeTheme.mono(9)).foregroundStyle(.white).lineLimit(1)
                        Text(b.timeText).font(GradeTheme.mono(8)).foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(3)
                }
                .offset(x: b.x, y: b.y)
                .onTapGesture { onSelectEvent(b.event) }
        }
    }

    private struct PlacedBlock: Identifiable {
        let id: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let color: Color
        let title: String
        let timeText: String
        let event: ClassEventItem
    }

    private func placedBlocks(colW: CGFloat) -> [PlacedBlock] {
        var out: [PlacedBlock] = []
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: weekStart)!
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let dayEvents = events.filter { $0.startAt >= dayStart && $0.startAt < dayEnd }
            guard !dayEvents.isEmpty else { continue }
            let placements = WeekGridLayout.columns(for: dayEvents.map {
                .init(id: $0.id, start: $0.startAt, end: $0.endAt)
            })
            for ev in dayEvents {
                let p = placements[ev.id] ?? .init(columnIndex: 0, columnCount: 1)
                let slot = colW / CGFloat(p.columnCount)
                let x = gutter + colW * CGFloat(i) + slot * CGFloat(p.columnIndex)
                // layout's dayStartHour is the display window's start, so this is
                // already relative to the top of the rendered grid.
                let y = max(0, CGFloat(layout.yOffset(for: ev.startAt, dayStart: dayStart,
                                                      calendar: cal)))
                // Clamp the block to the day boundary so late-night or multi-day
                // events don't draw past the bottom of the grid.
                let visibleEnd = min(ev.endAt, dayEnd)
                let h = CGFloat(layout.height(
                    forDurationSeconds: visibleEnd.timeIntervalSince(ev.startAt)))
                out.append(PlacedBlock(
                    id: ev.id, x: x, y: y, width: max(slot - 2, 1), height: h,
                    color: typeColor(ev.eventType), title: ev.title,
                    timeText: "\(Self.timeFmt.string(from: ev.startAt))–\(Self.timeFmt.string(from: ev.endAt))",
                    event: ev))
            }
        }
        return out
    }

    // MARK: Helpers

    private func shift(_ days: Int) {
        weekStart = cal.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
    }

    private func typeColor(_ id: String?) -> Color {
        guard let id, let t = store.eventTypes.first(where: { $0.id == id }) else { return .secondary }
        return GradeTheme.color(fromHex: t.colorHex)
    }

    private var weekRangeLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(Self.rangeFmt.string(from: weekStart)) – \(Self.rangeFmt.string(from: end))"
    }

    static func startOfWeek(_ date: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d"; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    private static let rangeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
