import Foundation
import SwiftUI
import AssistantShared

/// Owns all dashboard data and is the only object that talks to the daemon.
@MainActor
final class DashboardStore: ObservableObject {

    // Left rail
    @Published var summary: DashboardSummary?
    @Published var gpaRevealed = false

    // Calendar
    @Published var weekStart: Date = DashboardStore.startOfWeek(for: Date())
    @Published var events: [WeekEvent] = []

    // Chat
    @Published var messages: [ChatMessage] = []
    @Published var sessionId: String?
    @Published var isSending = false

    private var refreshTimer: Timer?

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
            Task { @MainActor in
                self?.refreshSummary()
                self?.refreshEvents()
            }
        }
    }

    // MARK: - Week navigation

    func shiftWeek(by weeks: Int) {
        let cal = Calendar(identifier: .gregorian)
        weekStart = cal.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        refreshEvents()
    }

    func goToToday() {
        weekStart = DashboardStore.startOfWeek(for: Date())
        refreshEvents()
    }

    // MARK: - Chat

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
        }
    }

    // MARK: - Calendar edits (optimistic)

    func createEvent(title: String, start: Date, end: Date) {
        XPCClient.shared.createCalendarEvent(
            CreateEventRequest(title: title, startAt: start, endAt: end, location: nil)
        ) { [weak self] result in
            if let ev = result.event { self?.events.append(ev) }
            self?.refreshEvents()
        }
    }

    func moveEvent(_ event: WeekEvent, newStart: Date, newEnd: Date) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = WeekEvent(id: event.id, title: event.title,
                                    startAt: newStart, endAt: newEnd,
                                    category: event.category, location: event.location)
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
}
