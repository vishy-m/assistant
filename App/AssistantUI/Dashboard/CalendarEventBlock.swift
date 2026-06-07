import SwiftUI
import AssistantShared

/// A calendar event block. The body drags to reschedule; an 8 pt bottom edge
/// drags to resize. Both snap to 15 minutes and commit optimistically.
struct CalendarEventBlock: View {
    let event: WeekEvent
    @ObservedObject var store: DashboardStore
    let layout: WeekGridLayout
    let dayStart: Date

    @State private var dragOffset: CGFloat = 0
    @State private var resizeDelta: CGFloat = 0
    @State private var showPopover = false

    /// Class events fill by event-type color; everything else by category.
    private var fillColor: Color {
        store.eventTypeColor(event.eventType) ?? store.categoryColor(event.category)
    }
    /// Dimmed when a class filter is active and this event isn't that class.
    /// Non-class events (courseId == nil) intentionally dim too, so the focused
    /// class stands out while the rest of the schedule recedes.
    private var isDimmed: Bool {
        if let filter = store.classFilter { return event.courseId != filter }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title).font(.caption2).bold().lineLimit(1)
            if let loc = event.location, !loc.isEmpty {
                Text(loc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fillColor.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(store.classColor(event.courseId) ?? .clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if let icon = store.classIcon(event.courseId) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(store.classColor(event.courseId) ?? .secondary)
                    .padding(2)
            }
        }
        .overlay(resizeHandle, alignment: .bottom)
        .opacity(isDimmed ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
        .offset(y: dragOffset)
        .padding(.bottom, -resizeDelta)
        .gesture(moveGesture, including: event.isRecurring ? .subviews : .all)
        .onTapGesture { showPopover = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [event.title, store.classTypeLabel(for: event)]
                .filter { !$0.isEmpty }.joined(separator: ", "))
        .popover(isPresented: $showPopover) {
            CalendarEventPopover(mode: .detail(event), store: store)
        }
    }

    @ViewBuilder
    private var resizeHandle: some View {
        if !event.isRecurring {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(height: 8)
                .gesture(resizeGesture)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { dragOffset = $0.translation.height }
            .onEnded { value in
                let deltaSeconds = secondsFor(points: value.translation.height)
                dragOffset = 0
                guard deltaSeconds != 0 else { return }
                store.moveEvent(event,
                                newStart: event.startAt.addingTimeInterval(deltaSeconds),
                                newEnd: event.endAt.addingTimeInterval(deltaSeconds))
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { resizeDelta = $0.translation.height }
            .onEnded { value in
                let deltaSeconds = secondsFor(points: value.translation.height)
                resizeDelta = 0
                let newEnd = event.endAt.addingTimeInterval(deltaSeconds)
                guard newEnd > event.startAt.addingTimeInterval(900) else { return }
                store.moveEvent(event, newStart: event.startAt, newEnd: newEnd)
            }
    }

    /// Converts a point delta to a 15-minute-snapped second delta.
    private func secondsFor(points: CGFloat) -> TimeInterval {
        let rawSeconds = Double(points) / layout.hourHeight * 3600
        let snap = 15.0 * 60
        return (rawSeconds / snap).rounded() * snap
    }
}
