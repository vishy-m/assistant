import Foundation

// MARK: - Raw LLM output (tolerant: every field optional; the normalizer drops
// what it can't parse, one entry at a time)

public struct RawRecurring: Codable, Equatable {
    public let kind: String?
    public let person: String?
    public let weekdays: [String]?
    public let startTime: String?
    public let endTime: String?
    public let location: String?
    enum CodingKeys: String, CodingKey {
        case kind, person, weekdays, location
        case startTime = "start_time", endTime = "end_time"
    }
    public init(kind: String?, person: String?, weekdays: [String]?,
                startTime: String?, endTime: String?, location: String?) {
        self.kind = kind; self.person = person; self.weekdays = weekdays
        self.startTime = startTime; self.endTime = endTime; self.location = location
    }
}

public struct RawDated: Codable, Equatable {
    public let kind: String?
    public let date: String?
    public let startTime: String?
    public let endTime: String?
    public let location: String?
    public let person: String?
    enum CodingKeys: String, CodingKey {
        case kind, date, location, person
        case startTime = "start_time", endTime = "end_time"
    }
    public init(kind: String?, date: String?, startTime: String?, endTime: String?,
                location: String?, person: String?) {
        self.kind = kind; self.date = date; self.startTime = startTime
        self.endTime = endTime; self.location = location; self.person = person
    }
}

public struct RawDeadline: Codable, Equatable {
    public let name: String?
    public let date: String?
    public let time: String?
    public let notes: String?
    public init(name: String?, date: String?, time: String?, notes: String?) {
        self.name = name; self.date = date; self.time = time; self.notes = notes
    }
}

public struct RawSyllabusExtraction: Codable, Equatable {
    public let semesterEnd: String?
    public let recurringEvents: [RawRecurring]?
    public let datedEvents: [RawDated]?
    public let deadlines: [RawDeadline]?
    enum CodingKeys: String, CodingKey {
        case deadlines
        case semesterEnd = "semester_end"
        case recurringEvents = "recurring_events"
        case datedEvents = "dated_events"
    }
    public init(semesterEnd: String?, recurringEvents: [RawRecurring]?,
                datedEvents: [RawDated]?, deadlines: [RawDeadline]?) {
        self.semesterEnd = semesterEnd; self.recurringEvents = recurringEvents
        self.datedEvents = datedEvents; self.deadlines = deadlines
    }
}

// MARK: - Prompt

public enum SyllabusPrompt {
    public static let toolName = "record_extraction"

    /// JSON Schema for the forced extraction tool. Dates are yyyy-MM-dd
    /// strings, times HH:mm (24h), weekdays lowercase English names.
    public static let toolSchemaJSON = """
    {"type":"object","properties":{
      "semester_end":{"type":"string","description":"Last day of the semester as yyyy-MM-dd, only if the document states it"},
      "recurring_events":{"type":"array","description":"Weekly repeating items: office hours, lecture times, weekly homework due patterns","items":{"type":"object","properties":{
        "kind":{"type":"string","enum":["office_hours","lecture","review","homework"]},
        "person":{"type":"string","description":"Professor or TA name for office hours"},
        "weekdays":{"type":"array","items":{"type":"string","enum":["sunday","monday","tuesday","wednesday","thursday","friday","saturday"]}},
        "start_time":{"type":"string","description":"HH:mm 24-hour"},
        "end_time":{"type":"string","description":"HH:mm 24-hour"},
        "location":{"type":"string"}},
        "required":["kind","weekdays","start_time"]}},
      "dated_events":{"type":"array","description":"Items on specific calendar dates: exams, review sessions, special lectures","items":{"type":"object","properties":{
        "kind":{"type":"string","enum":["exam","lecture","review","office_hours"]},
        "date":{"type":"string","description":"yyyy-MM-dd"},
        "start_time":{"type":"string"},
        "end_time":{"type":"string"},
        "location":{"type":"string"},
        "person":{"type":"string"}},
        "required":["kind","date"]}},
      "deadlines":{"type":"array","description":"Dated assignment/homework/project deadlines","items":{"type":"object","properties":{
        "name":{"type":"string","description":"Assignment name as written, e.g. 'HW3: Paging'"},
        "date":{"type":"string","description":"yyyy-MM-dd"},
        "time":{"type":"string","description":"HH:mm 24-hour if stated"},
        "notes":{"type":"string"}},
        "required":["name","date"]}}
    },"required":["recurring_events","dated_events","deadlines"]}
    """

    public static func build(className: String, todayISO: String,
                             documentText: String) -> String {
        """
        You extract structured schedule data from a course document (syllabus, \
        schedule, deadline sheet, or office-hours info) for the class "\(className)". \
        Today's date is \(todayISO).

        Call the \(toolName) tool exactly once with everything you find: office \
        hours, exams, review sessions, lecture times, homework/assignment \
        deadlines, and the semester end date if stated.

        PRIORITY RULE: if the document contains a dated schedule or calendar \
        (items on specific calendar dates), extract those as dated_events / \
        deadlines and DO NOT emit vague recurring patterns that duplicate them. \
        Use recurring_events only for information the dated schedule does not \
        cover (e.g. weekly office hours, or "homework due every Wednesday" when \
        no dated homework list exists).

        Dates must be yyyy-MM-dd. Times must be HH:mm 24-hour. Omit anything \
        the document does not state — never invent dates.

        DOCUMENT:
        \(documentText)
        """
    }
}

// MARK: - Normalizer

public enum SyllabusNormalizer {

    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7
    ]

    public static func normalize(_ raw: RawSyllabusExtraction, className: String,
                                 scanDate: Date, calendar: Calendar)
        -> (events: [SyllabusProposedEvent], tasks: [SyllabusProposedTask]) {

        let semesterEnd = raw.semesterEnd.flatMap { parseDate($0, calendar: calendar) }
        let until = semesterEnd ?? scanDate.addingTimeInterval(112 * 24 * 3600)

        var events: [SyllabusProposedEvent] = []

        for entry in raw.recurringEvents ?? [] {
            guard let kind = recurringKind(entry.kind),
                  let start = entry.startTime.flatMap(parseTime),
                  let weekdays = entry.weekdays?.compactMap({
                      weekdayNumbers[$0.lowercased()]
                  }), !weekdays.isEmpty
            else { continue }
            let end = entry.endTime.flatMap(parseTime)
            guard let firstStart = nextOccurrence(of: weekdays, atHour: start.h,
                                                  minute: start.m, onOrAfter: scanDate,
                                                  calendar: calendar) else { continue }
            let firstEnd = endDate(for: firstStart, endTime: end, calendar: calendar)
            events.append(SyllabusProposedEvent(
                kind: kind,
                title: kind == .officeHours
                    ? SyllabusTitles.officeHours(person: entry.person, className: className)
                    : SyllabusTitles.event(kind: kind, className: className),
                startAt: firstStart, endAt: firstEnd,
                location: blankToNil(entry.location),
                personName: blankToNil(entry.person),
                recurrence: RecurrenceRule(frequency: .weekly, interval: 1,
                                           byWeekday: weekdays.sorted(),
                                           untilDate: until, count: nil)))
        }

        for entry in raw.datedEvents ?? [] {
            guard let kind = datedKind(entry.kind),
                  let day = entry.date.flatMap({ parseDate($0, calendar: calendar) })
            else { continue }
            let start = entry.startTime.flatMap(parseTime) ?? (h: 9, m: 0)
            guard let startAt = calendar.date(bySettingHour: start.h, minute: start.m,
                                              second: 0, of: day) else { continue }
            let endAt = endDate(for: startAt, endTime: entry.endTime.flatMap(parseTime),
                                calendar: calendar)
            events.append(SyllabusProposedEvent(
                kind: kind,
                title: kind == .officeHours
                    ? SyllabusTitles.officeHours(person: entry.person, className: className)
                    : SyllabusTitles.event(kind: kind, className: className),
                startAt: startAt, endAt: endAt,
                location: blankToNil(entry.location),
                personName: blankToNil(entry.person),
                recurrence: nil))
        }

        var tasks: [SyllabusProposedTask] = []
        for entry in raw.deadlines ?? [] {
            guard let name = blankToNil(entry.name),
                  let day = entry.date.flatMap({ parseDate($0, calendar: calendar) })
            else { continue }
            let time = entry.time.flatMap(parseTime) ?? (h: 23, m: 59)
            guard let dueAt = calendar.date(bySettingHour: time.h, minute: time.m,
                                            second: 0, of: day) else { continue }
            tasks.append(SyllabusProposedTask(title: name, dueAt: dueAt,
                                              notes: blankToNil(entry.notes)))
        }

        return (events, tasks)
    }

    // MARK: helpers

    private static func recurringKind(_ raw: String?) -> SyllabusEventKind? {
        switch raw {
        case "office_hours": return .officeHours
        case "lecture": return .lecture
        case "review": return .review
        case "homework": return .homeworkPattern
        default: return nil
        }
    }

    private static func datedKind(_ raw: String?) -> SyllabusEventKind? {
        switch raw {
        case "exam": return .exam
        case "lecture": return .lecture
        case "review": return .review
        case "office_hours": return .officeHours
        default: return nil
        }
    }

    private static func parseDate(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1900, (1...12).contains(parts[1]),
              (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1],
                                                  day: parts[2]))
    }

    private static func parseTime(_ s: String) -> (h: Int, m: Int)? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    /// End = same day at endTime when parseable and after start; else start + 1h.
    private static func endDate(for start: Date, endTime: (h: Int, m: Int)?,
                                calendar: Calendar) -> Date {
        if let endTime,
           let candidate = calendar.date(bySettingHour: endTime.h, minute: endTime.m,
                                         second: 0, of: start),
           candidate > start {
            return candidate
        }
        return start.addingTimeInterval(3600)
    }

    /// Earliest date on/after `onOrAfter` whose weekday is in `weekdays`, at
    /// the given local time.
    private static func nextOccurrence(of weekdays: [Int], atHour hour: Int,
                                       minute: Int, onOrAfter: Date,
                                       calendar: Calendar) -> Date? {
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: onOrAfter),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute,
                                                second: 0, of: day)
            else { continue }
            if candidate >= onOrAfter || offset > 0 { return candidate }
        }
        return nil
    }

    private static func blankToNil(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }
}
