import Foundation

public struct TodayPlan: Codable, Equatable {
    public struct Item: Codable, Equatable {
        public enum Kind: String, Codable { case task, event }
        public var kind: Kind
        public var id: String
        public var title: String
        public var startAt: Date?    // events have start; tasks may omit
        public var dueAt: Date?      // tasks have due; events omit
        public var location: String?
        public var category: String

        public init(kind: Kind, id: String, title: String,
                    startAt: Date?, dueAt: Date?, location: String?, category: String) {
            self.kind = kind
            self.id = id
            self.title = title
            self.startAt = startAt
            self.dueAt = dueAt
            self.location = location
            self.category = category
        }
    }

    public let items: [Item]

    public init(items: [Item]) { self.items = items }

    public static func empty() -> TodayPlan { TodayPlan(items: []) }
}
