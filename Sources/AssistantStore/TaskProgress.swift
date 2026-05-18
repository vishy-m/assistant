import Foundation

/// Completion progress for a set of tasks — the fraction backing the ring.
public enum TaskProgress {
    /// Completed ÷ total. Returns 0 for an empty list.
    public static func fraction(_ tasks: [Task]) -> Double {
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter { $0.completedAt != nil }.count
        return Double(done) / Double(tasks.count)
    }
}
