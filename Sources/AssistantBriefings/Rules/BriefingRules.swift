import Foundation
import AssistantStore

public struct BriefingRules {

    private let db: AssistantDB
    private let clock: @Sendable () -> Date

    public init(db: AssistantDB, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.db = db
        self.clock = clock
    }

    public func evaluate() throws -> [RiskFinding] {
        var findings: [RiskFinding] = []
        findings.append(contentsOf: try clusteredDeadlines())
        findings.append(contentsOf: try assignmentsDueSoon())
        // gradeBelowTarget evaluated by sub-plan #7's grade hooks; we omit here
        // until that hook is in place to avoid double-evaluation.
        return findings
    }

    /// ≥3 deadlines in next 48h with no time blocked in GCal.
    private func clusteredDeadlines() throws -> [RiskFinding] {
        let now = clock()
        let cutoff = now.addingTimeInterval(48 * 3600)
        let taskRepo = TaskRepository(db: db)
        let gcalRepo = GCalRepository(db: db)

        let upcoming: [AssistantStore.Task] = try gatherTasks(taskRepo: taskRepo,
                                                              from: now, to: cutoff)
        guard upcoming.count >= 3 else { return [] }

        // Count "study blocks" in the next 48h
        let events = try gcalRepo.eventsOn(date: now)
        let nextDayEvents = try gcalRepo.eventsOn(date: now.addingTimeInterval(86_400))
        let totalBlocks = (events + nextDayEvents)
            .filter { $0.category == "study" || $0.title.lowercased().contains("study") }
            .count
        guard totalBlocks == 0 else { return [] }

        let titles = upcoming.prefix(5).map { $0.title }
        let payload: [String: Any] = [
            "task_count": upcoming.count,
            "titles": Array(titles)
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return [RiskFinding(
            kind: .clusteredDeadlines,
            summary: "\(upcoming.count) deadlines in 48h with no study blocks",
            payloadJSON: String(data: data, encoding: .utf8) ?? "{}"
        )]
    }

    /// A parsed assignment is due in <24h and not completed.
    private func assignmentsDueSoon() throws -> [RiskFinding] {
        let now = clock()
        let cutoff = now.addingTimeInterval(24 * 3600)
        let repo = TaskRepository(db: db)
        let candidates = try gatherTasks(taskRepo: repo, from: now, to: cutoff)
            .filter { $0.source == "parsed" && $0.completedAt == nil }
        return candidates.map { t in
            let payload: [String: Any] = ["task_id": t.id, "title": t.title,
                                           "due_at": ISO8601DateFormatter().string(from: t.dueAt ?? now)]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            return RiskFinding(
                kind: .assignmentDueSoon,
                summary: "Assignment due in <24h: \(t.title)",
                payloadJSON: String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    private func gatherTasks(taskRepo: TaskRepository,
                              from start: Date, to end: Date) throws -> [AssistantStore.Task] {
        // No range query helper yet — iterate per-day. For a 48h window that's 1-2 days.
        let cal = Calendar(identifier: .gregorian)
        var results: [AssistantStore.Task] = []
        var cursor = cal.startOfDay(for: start)
        while cursor < end {
            results.append(contentsOf: try taskRepo.dueOn(date: cursor))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        // Filter completed and outside window
        return results.filter {
            $0.completedAt == nil &&
            ($0.dueAt ?? .distantFuture) >= start &&
            ($0.dueAt ?? .distantPast) <= end
        }
    }
}
