import Foundation

/// Merges incomplete dated tasks and ungraded dated grade items into one
/// upcoming list. Overdue entries sort first, then soonest-due first.
public enum DueSoonAggregator {

    public struct Entry: Equatable {
        public enum Kind: String { case task, gradeItem }
        public let kind: Kind
        public let id: String
        public let title: String
        public let courseId: String?
        public let category: String?
        public let dueAt: Date
        public let isOverdue: Bool
    }

    public static func aggregate(tasks: [Task],
                                 gradeItems: [GradeItem],
                                 now: Date,
                                 horizonDays: Int = 7) -> [Entry] {
        let cal = Calendar(identifier: .gregorian)
        guard let horizon = cal.date(byAdding: .day, value: horizonDays, to: now) else {
            return []
        }
        var entries: [Entry] = []
        for t in tasks {
            guard t.completedAt == nil, let due = t.dueAt, due <= horizon else { continue }
            entries.append(Entry(kind: .task, id: t.id, title: t.title,
                                  courseId: t.courseId, category: t.category,
                                  dueAt: due, isOverdue: due < now))
        }
        for gi in gradeItems {
            guard gi.earnedPoints == nil, let due = gi.dueAt, due <= horizon else { continue }
            entries.append(Entry(kind: .gradeItem, id: gi.id, title: gi.name,
                                  courseId: gi.courseId, category: nil,
                                  dueAt: due, isOverdue: due < now))
        }
        return entries.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            return a.dueAt < b.dueAt
        }
    }
}
