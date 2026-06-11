import SwiftUI
import AssistantShared

/// A scrollable week time-grid of this class's events, colored by event type.
/// Reuses WeekGridLayout for geometry. Tapping an event calls `onSelectEvent`.
struct ClassWeekCalendar: View {
    @ObservedObject var store: ClassStore
    let events: [ClassEventItem]
    var onSelectEvent: (ClassEventItem) -> Void

    @State private var weekStart: Date = ClassWeekCalendar.startOfWeek(Date())

    private let cal = Calendar(identifier: .gregorian)
    private let hourHeight: Double = 40
    private let gutter: CGFloat = 34

    private var layout: WeekGridLayout {
        WeekGridLayout(hourHeight: hourHeight, dayStartHour: 0)
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
                            gridLines(colW: colW)
                            blocks(colW: colW)
                        }
                        .frame(height: CGFloat(24) * CGFloat(hourHeight))
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
        .padding(.vertical, 2)
    }

    // MARK: Grid + blocks

    private func gridLines(colW: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            let y = CGFloat(hour) * CGFloat(hourHeight)
            Group {
                Text(String(format: "%02d", hour))
                    .font(GradeTheme.mono(8)).foregroundStyle(.tertiary)
                    .frame(width: gutter - 4, alignment: .trailing)
                    .offset(x: 0, y: y - 4)
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: colW * 7, height: 1)
                    .offset(x: gutter, y: y)
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
                let y = max(0, CGFloat(layout.yOffset(for: ev.startAt, dayStart: dayStart)))
                // Clamp the block to the day boundary so late-night or multi-day
                // events don't draw past the bottom of the 24h grid.
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
