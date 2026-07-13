import Foundation

/// What kind of calendar event a syllabus proposal is.
public enum SyllabusEventKind: String, Codable {
    case officeHours, exam, lecture, review, homeworkPattern
}

/// A calendar event the scanner proposes; the user approves it in the review
/// sheet before anything is created.
public struct SyllabusProposedEvent: Codable, Equatable, Identifiable {
    public let id: String
    public let kind: SyllabusEventKind
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let location: String?
    public let personName: String?
    public let recurrence: RecurrenceRule?

    public init(id: String = UUID().uuidString, kind: SyllabusEventKind, title: String,
                startAt: Date, endAt: Date, location: String?, personName: String?,
                recurrence: RecurrenceRule?) {
        self.id = id; self.kind = kind; self.title = title
        self.startAt = startAt; self.endAt = endAt
        self.location = location; self.personName = personName
        self.recurrence = recurrence
    }
}

/// A dated deadline the scanner proposes as a task (never a calendar event).
public struct SyllabusProposedTask: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let dueAt: Date
    public let notes: String?

    public init(id: String = UUID().uuidString, title: String, dueAt: Date, notes: String?) {
        self.id = id; self.title = title; self.dueAt = dueAt; self.notes = notes
    }
}

/// Scan outcome as a value — failures cross XPC as data, never as errors.
public enum SyllabusScanStatus: Codable, Equatable {
    case ok
    case nothingToScan
    case llmUnavailable
    case failed(String)

    private enum CodingKeys: String, CodingKey { case code, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decode(String.self, forKey: .code)
        switch code {
        case "ok": self = .ok
        case "nothingToScan": self = .nothingToScan
        case "llmUnavailable": self = .llmUnavailable
        default: self = .failed(try c.decodeIfPresent(String.self, forKey: .message) ?? code)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ok: try c.encode("ok", forKey: .code)
        case .nothingToScan: try c.encode("nothingToScan", forKey: .code)
        case .llmUnavailable: try c.encode("llmUnavailable", forKey: .code)
        case .failed(let message):
            try c.encode("failed", forKey: .code)
            try c.encode(message, forKey: .message)
        }
    }
}

public struct SyllabusScanResult: Codable, Equatable, Identifiable {
    public let fileId: String
    public let status: SyllabusScanStatus
    public let events: [SyllabusProposedEvent]
    public let tasks: [SyllabusProposedTask]

    public var id: String { fileId }

    public init(fileId: String, status: SyllabusScanStatus,
                events: [SyllabusProposedEvent], tasks: [SyllabusProposedTask]) {
        self.fileId = fileId; self.status = status
        self.events = events; self.tasks = tasks
    }
}

/// Spec'd title formats. No numbering anywhere (user decision).
public enum SyllabusTitles {
    public static func homework(className: String) -> String { "[hmwk] [\(className)]" }
    public static func exam(className: String) -> String { "[exam] [\(className)]" }

    public static func officeHours(person: String?, className: String) -> String {
        let trimmed = person?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "[OH] [\(className)]" : "[OH] [\(trimmed)] [\(className)]"
    }

    public static func event(kind: SyllabusEventKind, className: String) -> String {
        switch kind {
        case .officeHours: return officeHours(person: nil, className: className)
        case .exam: return exam(className: className)
        case .homeworkPattern: return homework(className: className)
        case .lecture: return "[lecture] [\(className)]"
        case .review: return "[review] [\(className)]"
        }
    }
}
