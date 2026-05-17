import Foundation

/// One payload backing the dashboard's left rail.
public struct DashboardSummary: Codable {
    public let gpa: Double
    public let gpaCountedCourses: Int
    public let gpaTotalCourses: Int
    public let classes: [ClassStanding]
    public let recentGrades: [RecentGrade]
    public let dueSoon: [DueSoonItem]

    public init(gpa: Double, gpaCountedCourses: Int, gpaTotalCourses: Int,
                classes: [ClassStanding], recentGrades: [RecentGrade],
                dueSoon: [DueSoonItem]) {
        self.gpa = gpa
        self.gpaCountedCourses = gpaCountedCourses
        self.gpaTotalCourses = gpaTotalCourses
        self.classes = classes
        self.recentGrades = recentGrades
        self.dueSoon = dueSoon
    }
}

public struct ClassStanding: Codable, Identifiable {
    public var id: String { courseId }
    public let courseId: String
    public let courseName: String
    public let currentPct: Double
    public let currentLetter: String
    public init(courseId: String, courseName: String,
                currentPct: Double, currentLetter: String) {
        self.courseId = courseId
        self.courseName = courseName
        self.currentPct = currentPct
        self.currentLetter = currentLetter
    }
}

public struct RecentGrade: Codable, Identifiable {
    public var id: String { itemId }
    public let itemId: String
    public let courseName: String
    public let itemName: String
    public let earnedPct: Double
    public let enteredAt: Date
    public init(itemId: String, courseName: String, itemName: String,
                earnedPct: Double, enteredAt: Date) {
        self.itemId = itemId
        self.courseName = courseName
        self.itemName = itemName
        self.earnedPct = earnedPct
        self.enteredAt = enteredAt
    }
}

public struct DueSoonItem: Codable, Identifiable {
    public enum Kind: String, Codable { case task, gradeItem }
    public let id: String
    public let kind: Kind
    public let title: String
    public let courseName: String?
    public let dueAt: Date
    public let isOverdue: Bool
    public init(id: String, kind: Kind, title: String, courseName: String?,
                dueAt: Date, isOverdue: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.courseName = courseName
        self.dueAt = dueAt
        self.isOverdue = isOverdue
    }
}

public struct WeekEvent: Codable, Identifiable {
    public let id: String
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let category: String
    public let location: String?
    public init(id: String, title: String, startAt: Date, endAt: Date,
                category: String, location: String?) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.category = category
        self.location = location
    }
}

public struct WeekEventsResponse: Codable {
    public let events: [WeekEvent]
    public init(events: [WeekEvent]) { self.events = events }
}

public struct CreateEventRequest: Codable {
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let location: String?
    public init(title: String, startAt: Date, endAt: Date, location: String?) {
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.location = location
    }
}

public struct UpdateEventRequest: Codable {
    public let eventId: String
    public let startAt: Date
    public let endAt: Date
    public init(eventId: String, startAt: Date, endAt: Date) {
        self.eventId = eventId
        self.startAt = startAt
        self.endAt = endAt
    }
}

/// Result of a calendar write: the stored event, or an error message.
public struct CalendarWriteResult: Codable {
    public let event: WeekEvent?
    public let errorMessage: String?
    public init(event: WeekEvent?, errorMessage: String?) {
        self.event = event
        self.errorMessage = errorMessage
    }
}
