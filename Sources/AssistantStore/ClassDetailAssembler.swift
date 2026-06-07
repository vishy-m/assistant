import Foundation
import AssistantShared

/// Pure mappers from store records to the Classes-window DTOs. No I/O.
public enum ClassDetailAssembler {

    public static func summary(course: Course,
                               events: [GCalEventCache],
                               tasks: [Task]) -> ClassSummary {
        ClassSummary(
            id: course.id, name: course.name, term: course.term,
            colorHex: course.color, iconName: course.iconName,
            professorName: course.professorName, classroom: course.classroom,
            openTaskCount: tasks.filter { $0.completedAt == nil }.count,
            scheduleEventCount: events.count)
    }

    public static func detail(course: Course,
                              events: [GCalEventCache],
                              tasks: [Task]) -> ClassDetail {
        let eventItems = events
            .sorted { $0.startAt < $1.startAt }
            .map { ClassEventItem(id: $0.gcalEventId, title: $0.title,
                                  startAt: $0.startAt, endAt: $0.endAt,
                                  eventType: $0.eventType) }
        let taskItems = tasks
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .map { ClassTaskItem(id: $0.id, title: $0.title, dueAt: $0.dueAt,
                                 isCompleted: $0.completedAt != nil) }
        return ClassDetail(
            id: course.id, name: course.name, term: course.term,
            colorHex: course.color, iconName: course.iconName,
            professorName: course.professorName, professorEmail: course.professorEmail,
            classroom: course.classroom, events: eventItems, tasks: taskItems)
    }
}
