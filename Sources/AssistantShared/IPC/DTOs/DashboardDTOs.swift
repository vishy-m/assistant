import Foundation

/// One payload backing the dashboard's left rail.
public struct DashboardSummary: Codable, Equatable {
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

public struct ClassStanding: Codable, Identifiable, Equatable {
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

public struct RecentGrade: Codable, Identifiable, Equatable {
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

public struct DueSoonItem: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable, Equatable { case task, gradeItem }
    public let id: String
    public let kind: Kind
    public let title: String
    public let courseName: String?
    public let category: String?
    public let dueAt: Date
    public let isOverdue: Bool
    public init(id: String, kind: Kind, title: String, courseName: String?,
                category: String? = nil, dueAt: Date, isOverdue: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.courseName = courseName
        self.category = category
        self.dueAt = dueAt
        self.isOverdue = isOverdue
    }
}

public struct WeekEvent: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let category: String
    public let location: String?
    public let isRecurring: Bool
    public let courseId: String?
    public let eventType: String?
    public init(id: String, title: String, startAt: Date, endAt: Date,
                category: String, location: String?, isRecurring: Bool = false,
                courseId: String? = nil, eventType: String? = nil) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.category = category
        self.location = location
        self.isRecurring = isRecurring
        self.courseId = courseId
        self.eventType = eventType
    }

    // Custom decoder so responses from an older daemon — which omit newer keys —
    // decode with defaults/nils instead of throwing keyNotFound, which would
    // blank the calendar on any app/daemon version skew.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startAt = try c.decode(Date.self, forKey: .startAt)
        endAt = try c.decode(Date.self, forKey: .endAt)
        category = try c.decode(String.self, forKey: .category)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
    }
}

public struct WeekEventsResponse: Codable, Equatable {
    public let events: [WeekEvent]
    public init(events: [WeekEvent]) { self.events = events }
}

public struct CreateEventRequest: Codable, Equatable {
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let location: String?
    public let category: String
    public let recurrence: RecurrenceRule?
    public let courseId: String?
    public let eventType: String?
    public init(title: String, startAt: Date, endAt: Date,
                location: String?, category: String = "Misc",
                recurrence: RecurrenceRule? = nil,
                courseId: String? = nil, eventType: String? = nil) {
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.location = location
        self.category = category
        self.recurrence = recurrence
        self.courseId = courseId
        self.eventType = eventType
    }
}

public struct EventTypeDTO: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let colorHex: String
    public let symbolName: String?
    public let isBuiltin: Bool
    public init(id: String, name: String, colorHex: String,
                symbolName: String?, isBuiltin: Bool) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.isBuiltin = isBuiltin
    }
}

public struct ClassSummary: Codable, Identifiable, Equatable {
    public let id: String          // course id
    public let name: String
    public let term: String?
    public let colorHex: String?
    public let iconName: String?
    public let professorName: String?
    public let classroom: String?
    public let openTaskCount: Int
    public let scheduleEventCount: Int
    public init(id: String, name: String, term: String?, colorHex: String?,
                iconName: String?, professorName: String?, classroom: String?,
                openTaskCount: Int, scheduleEventCount: Int) {
        self.id = id
        self.name = name
        self.term = term
        self.colorHex = colorHex
        self.iconName = iconName
        self.professorName = professorName
        self.classroom = classroom
        self.openTaskCount = openTaskCount
        self.scheduleEventCount = scheduleEventCount
    }
}

public struct ClassEventItem: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let eventType: String?
    public init(id: String, title: String, startAt: Date, endAt: Date, eventType: String?) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.eventType = eventType
    }
}

public struct ClassTaskItem: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let dueAt: Date?
    public let isCompleted: Bool
    public init(id: String, title: String, dueAt: Date?, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.isCompleted = isCompleted
    }
}

public struct ClassDetail: Codable, Identifiable, Equatable {
    public let id: String          // course id
    public let name: String
    public let term: String?
    public let colorHex: String?
    public let iconName: String?
    public let professorName: String?
    public let professorEmail: String?
    public let classroom: String?
    public let events: [ClassEventItem]
    public let tasks: [ClassTaskItem]
    public init(id: String, name: String, term: String?, colorHex: String?,
                iconName: String?, professorName: String?, professorEmail: String?,
                classroom: String?, events: [ClassEventItem], tasks: [ClassTaskItem]) {
        self.id = id
        self.name = name
        self.term = term
        self.colorHex = colorHex
        self.iconName = iconName
        self.professorName = professorName
        self.professorEmail = professorEmail
        self.classroom = classroom
        self.events = events
        self.tasks = tasks
    }
}

public struct UpdateEventRequest: Codable, Equatable {
    public let eventId: String
    public let startAt: Date
    public let endAt: Date
    public let title: String?
    public init(eventId: String, startAt: Date, endAt: Date, title: String? = nil) {
        self.eventId = eventId
        self.startAt = startAt
        self.endAt = endAt
        self.title = title
    }
}

/// Result of a calendar write: the stored event, or an error message.
public struct CalendarWriteResult: Codable, Equatable {
    public let event: WeekEvent?
    public let errorMessage: String?
    public init(event: WeekEvent?, errorMessage: String?) {
        self.event = event
        self.errorMessage = errorMessage
    }
}

public struct WeekTask: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let dueAt: Date
    public let category: String
    public init(id: String, title: String, dueAt: Date, category: String) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.category = category
    }
}

public struct WeekTasksResponse: Codable, Equatable {
    public let tasks: [WeekTask]
    public init(tasks: [WeekTask]) { self.tasks = tasks }
}
