import Foundation
import SwiftUI
import AssistantShared
import AssistantStore

/// Owns all dashboard data and is the only object that talks to the daemon.
@MainActor
final class DashboardStore: ObservableObject {

    // Left rail
    @Published var summary: DashboardSummary?
    @Published var gpaRevealed = false

    // Calendar
    @Published var weekStart: Date = DashboardStore.startOfWeek(for: Date())
    @Published var events: [WeekEvent] = []
    @Published var weekTasks: [WeekTask] = []
    @Published var categories: [AssistantStore.Category] = []
    @Published var eventTypes: [EventTypeDTO] = []
    @Published var courses: [Course] = []
    @Published var classSummaries: [ClassSummary] = []
    /// When set to a course id, the calendar dims events of other classes.
    @Published var classFilter: String?

    // Chat
    @Published var messages: [ChatMessage] = []
    @Published var sessionId: String?
    @Published var isSending = false

    private var refreshTimer: Timer?
    private var changeObserver: NSObjectProtocol?

    init() {
        // Keep the calendar's task deadline lines in sync with edits made in any
        // other window (Tasks window, class panels).
        changeObserver = NotificationCenter.default.addObserver(
            forName: .assistantTasksDidChange, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.refreshTasks() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    struct ChatMessage: Identifiable {
        enum Role { case user, assistant, system }
        let id = UUID()
        let role: Role
        let text: String
    }

    static func startOfWeek(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = Calendar.current.firstWeekday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    var weekEnd: Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    // MARK: - Loading

    func refreshAll() {
        refreshSummary()
        refreshEvents()
        refreshTasks()
        refreshCategories()
        refreshEventTypes()
        refreshClasses()
        loadChatHistory()
        startTimer()
    }

    func refreshSummary() {
        XPCClient.shared.getDashboardSummary { [weak self] summary in
            self?.summary = summary
        }
    }

    func refreshEvents() {
        XPCClient.shared.getWeekEvents(start: weekStart, end: weekEnd) { [weak self] events in
            self?.events = events
        }
    }

    func refreshTasks() {
        XPCClient.shared.getWeekTasks(start: weekStart, end: weekEnd) { [weak self] tasks in
            self?.weekTasks = tasks
        }
    }

    func refreshCategories() {
        XPCClient.shared.listCategories { [weak self] cats in
            self?.categories = cats
        }
    }

    func refreshEventTypes() {
        XPCClient.shared.listEventTypes { [weak self] types in
            self?.eventTypes = types
        }
    }

    func refreshClasses() {
        XPCClient.shared.listCourses { [weak self] courses in
            self?.courses = courses
        }
        XPCClient.shared.listClasses { [weak self] summaries in
            self?.classSummaries = summaries
        }
    }

    func saveEventType(_ type: EventTypeDTO) {
        XPCClient.shared.upsertEventType(type) { [weak self] _ in
            self?.refreshEventTypes()
            self?.refreshEvents()
        }
    }

    func deleteEventType(id: String) {
        XPCClient.shared.deleteEventType(id: id) { [weak self] _ in
            self?.refreshEventTypes()
            self?.refreshEvents()
        }
    }

    /// Resolves a category name to its color. Unknown/nil → the default
    /// category's color, or a neutral fallback.
    func categoryColor(_ name: String?) -> Color {
        if let name,
           let match = categories.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return GradeTheme.color(fromHex: match.colorHex)
        }
        if let def = categories.first(where: { $0.isDefault }) {
            return GradeTheme.color(fromHex: def.colorHex)
        }
        return GradeTheme.color(fromHex: "8A8F98")
    }

    /// The fill color for an event type id, or nil if unknown/unset.
    func eventTypeColor(_ id: String?) -> Color? {
        guard let id, let t = eventTypes.first(where: { $0.id == id }) else { return nil }
        return GradeTheme.color(fromHex: t.colorHex)
    }

    /// A class's identity (border/glyph) color from its Course.color, or nil.
    func classColor(_ courseId: String?) -> Color? {
        guard let courseId,
              let c = courses.first(where: { $0.id == courseId }),
              let hex = c.color else { return nil }
        return GradeTheme.color(fromHex: hex)
    }

    /// A class's SF Symbol glyph name, or nil.
    func classIcon(_ courseId: String?) -> String? {
        guard let courseId,
              let c = courses.first(where: { $0.id == courseId }) else { return nil }
        return c.iconName
    }

    /// "Course Name — Type Name" for accessibility, omitting absent parts.
    func classTypeLabel(for event: WeekEvent) -> String {
        var parts: [String] = []
        if let cid = event.courseId,
           let c = courses.first(where: { $0.id == cid }) { parts.append(c.name) }
        if let tid = event.eventType,
           let t = eventTypes.first(where: { $0.id == tid }) { parts.append(t.name) }
        return parts.joined(separator: " — ")
    }

    func saveCategory(originalName: String?, name: String, colorHex: String) {
        XPCClient.shared.saveCategory(originalName: originalName, name: name,
                                      colorHex: colorHex) { [weak self] _ in
            self?.refreshCategories()
            self?.refreshEvents()
        }
    }

    func deleteCategory(name: String) {
        XPCClient.shared.removeCategory(name: name) { [weak self] _ in
            self?.refreshCategories()
            self?.refreshEvents()
        }
    }

    func setEventCategory(_ event: WeekEvent, category: String) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = WeekEvent(id: event.id, title: event.title,
                                    startAt: event.startAt, endAt: event.endAt,
                                    category: category, location: event.location,
                                    isRecurring: event.isRecurring,
                                    courseId: event.courseId, eventType: event.eventType)
        }
        XPCClient.shared.setEventCategory(eventId: event.id, category: category) { [weak self] ok in
            if !ok { self?.refreshEvents() }
        }
    }

    func setEventClassification(_ event: WeekEvent, courseId: String?, eventType: String?) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = WeekEvent(id: event.id, title: event.title,
                                    startAt: event.startAt, endAt: event.endAt,
                                    category: event.category, location: event.location,
                                    isRecurring: event.isRecurring,
                                    courseId: courseId, eventType: eventType)
        }
        XPCClient.shared.setEventClassification(
            eventId: event.id, courseId: courseId, eventType: eventType) { [weak self] ok in
            if !ok { self?.refreshEvents() }
        }
    }

    func loadChatHistory() {
        XPCClient.shared.getMostRecentSessionId { [weak self] sid in
            guard let self, let sid else { return }
            self.sessionId = sid
            XPCClient.shared.getMessages(sessionId: sid) { msgs in
                self.messages = msgs.map { m in
                    ChatMessage(role: m.role == "assistant" ? .assistant : .user,
                                text: m.content)
                }
            }
        }
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.refreshSummary()
                self?.refreshEvents()
                self?.refreshTasks()
            }
        }
    }

    // MARK: - Week navigation

    func shiftWeek(by weeks: Int) {
        let cal = Calendar(identifier: .gregorian)
        weekStart = cal.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        refreshEvents()
        refreshTasks()
    }

    func goToToday() {
        weekStart = DashboardStore.startOfWeek(for: Date())
        refreshEvents()
        refreshTasks()
    }

    // MARK: - Chat

    /// Clears the dashboard chat panel and starts a fresh conversation — the
    /// next prompt creates a new session.
    func clearChat() {
        messages = []
        sessionId = nil
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isSending = true
        XPCClient.shared.submitPrompt(text: trimmed, sessionId: sessionId) { [weak self] result in
            guard let self else { return }
            self.isSending = false
            switch result {
            case .success(let resp):
                if let err = resp.errorMessage {
                    self.messages.append(ChatMessage(role: .system, text: "Error: \(err)"))
                } else {
                    self.sessionId = resp.sessionId
                    self.messages.append(ChatMessage(
                        role: .assistant,
                        text: resp.text.isEmpty ? "(done — actions completed)" : resp.text))
                }
            case .failure(let err):
                self.messages.append(ChatMessage(role: .system, text: "Error: \(err)"))
            }
            self.refreshSummary()
            self.refreshEvents()
            self.refreshTasks()
        }
    }

    // MARK: - Calendar edits (optimistic)

    func createEvent(title: String, start: Date, end: Date, category: String,
                     recurrence: RecurrenceRule? = nil,
                     courseId: String? = nil, eventType: String? = nil) {
        XPCClient.shared.createCalendarEvent(
            CreateEventRequest(title: title, startAt: start, endAt: end,
                               location: nil, category: category,
                               recurrence: recurrence,
                               courseId: courseId, eventType: eventType)
        ) { [weak self] result in
            // Recurring create returns the master event id, which sync never
            // surfaces (singleEvents=true expands to instance ids); appending
            // it would leave a phantom row until the next refresh.
            if let ev = result.event, recurrence == nil { self?.events.append(ev) }
            self?.refreshEvents()
        }
    }

    func moveEvent(_ event: WeekEvent, newStart: Date, newEnd: Date) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = WeekEvent(id: event.id, title: event.title,
                                    startAt: newStart, endAt: newEnd,
                                    category: event.category, location: event.location,
                                    isRecurring: event.isRecurring,
                                    courseId: event.courseId, eventType: event.eventType)
        }
        XPCClient.shared.updateCalendarEvent(
            UpdateEventRequest(eventId: event.id, startAt: newStart, endAt: newEnd)
        ) { [weak self] ok in
            if !ok { self?.refreshEvents() }
        }
    }

    func deleteEvent(_ event: WeekEvent) {
        events.removeAll { $0.id == event.id }
        XPCClient.shared.deleteCalendarEvent(eventId: event.id) { [weak self] ok in
            if !ok { self?.refreshEvents() }
        }
    }

    // MARK: - Task edits (optimistic)

    func rescheduleTask(_ task: WeekTask, newDue: Date) {
        if let idx = weekTasks.firstIndex(where: { $0.id == task.id }) {
            weekTasks[idx] = WeekTask(id: task.id, title: task.title,
                                      dueAt: newDue, category: task.category)
        }
        XPCClient.shared.rescheduleTask(taskId: task.id, dueAt: newDue) { [weak self] ok in
            self?.refreshSummary()
            if !ok { self?.refreshTasks() }
        }
    }

    func completeTask(_ task: WeekTask) {
        weekTasks.removeAll { $0.id == task.id }
        XPCClient.shared.completeTask(taskId: task.id) { [weak self] ok in
            self?.refreshSummary()
            if !ok { self?.refreshTasks() }
        }
    }
}
