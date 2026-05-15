import Foundation

public enum BriefingTemplates {

    public static func morning(items: [String]) -> String {
        guard !items.isEmpty else { return "Nothing scheduled. Enjoy the quiet." }
        let bullets = items.prefix(8).map { "• \($0)" }.joined(separator: "\n")
        return "Today:\n\(bullets)"
    }

    public static func evening(remaining: [String], tomorrow: [String]) -> String {
        var parts: [String] = []
        if !remaining.isEmpty {
            parts.append("Still on the list:\n" + remaining.prefix(5).map { "• \($0)" }.joined(separator: "\n"))
        }
        if !tomorrow.isEmpty {
            parts.append("Tomorrow:\n" + tomorrow.prefix(5).map { "• \($0)" }.joined(separator: "\n"))
        }
        return parts.isEmpty ? "All caught up. Good night." : parts.joined(separator: "\n\n")
    }

    public static func preEvent(title: String, minutesUntil: Int) -> String {
        "\(title) in \(minutesUntil) min."
    }

    public static func clusteredDeadlines(count: Int) -> String {
        "\(count) deadlines in the next 48h with no study time blocked. Want help finding a slot?"
    }

    public static func assignmentDueSoon(title: String, hoursUntil: Int) -> String {
        "\"\(title)\" is due in ~\(hoursUntil)h and isn't marked done. Open it?"
    }
}
