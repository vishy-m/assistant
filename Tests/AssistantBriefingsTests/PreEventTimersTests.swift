import XCTest
@testable import AssistantBriefings
@testable import AssistantShared
@testable import AssistantStore

final class PreEventTimersTests: XCTestCase {

    private let chicago: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal
    }()

    // MARK: - A2-13 saved lead times

    func testExamCategoryUsesSavedExamLeadsNotGeneric() async {
        var settings = AppSettings.default
        settings.leadTimes.exam = [90, 30]
        settings.leadTimes.generic = [15]
        let timers = PreEventTimers(leadTimesByCategory: PreEventTimers.leadTimes(from: settings))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(100 * 60)
        let event = makeEvent(id: "exam", title: "Midterm", start: start, category: "Exam", eventType: nil)

        let fires = await timers.upcomingFires(events: [event], now: now, window: 3 * 3600)

        XCTAssertEqual(fires.map(\.leadMinutes), [90, 30])
    }

    func testEventTypeExamUsesExamLeadsWhenCategoryIsMisc() async {
        var settings = AppSettings.default
        settings.leadTimes.exam = [1440, 60]
        settings.leadTimes.generic = [15]
        let timers = PreEventTimers(leadTimesByCategory: PreEventTimers.leadTimes(from: settings))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(1440 * 60 + 30)
        let event = makeEvent(id: "misc-exam", title: "Final", start: start, category: "Misc", eventType: "exam")

        let fires = await timers.upcomingFires(events: [event], now: now, window: 90)

        XCTAssertEqual(fires.map(\.leadMinutes), [1440])
    }

    func testEventTypeClassBeatsExamCategory() async {
        var settings = AppSettings.default
        settings.leadTimes.exam = [1440, 60]
        settings.leadTimes.classCategory = [10]
        let timers = PreEventTimers(leadTimesByCategory: PreEventTimers.leadTimes(from: settings))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(10 * 60 + 30)
        let event = makeEvent(id: "typed-class", title: "Lecture", start: start, category: "Exam", eventType: "class")

        let fires = await timers.upcomingFires(events: [event], now: now, window: 90)

        XCTAssertEqual(fires.map(\.leadMinutes), [10])
    }

    func testCustomExamLeadFiresSixtyMinutesBeforeNotDayBefore() async {
        var settings = AppSettings.default
        settings.leadTimes.exam = [60]
        settings.leadTimes.generic = [15]
        let timers = PreEventTimers(leadTimesByCategory: PreEventTimers.leadTimes(from: settings))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(1440 * 60 + 120)
        let event = makeEvent(id: "exam60", title: "Quiz", start: start, category: "Exam")

        let fires = await timers.upcomingFires(events: [event], now: now, window: 25 * 3600)

        XCTAssertEqual(fires.map(\.leadMinutes), [60])
        XCTAssertEqual(fires.first?.fireAt, start.addingTimeInterval(-60 * 60))
        XCTAssertFalse(fires.contains { $0.leadMinutes == 1440 })
    }

    func testPersonalCategoryUsesCustomGenericLead() async {
        var settings = AppSettings.default
        settings.leadTimes.generic = [5]
        let timers = PreEventTimers(leadTimesByCategory: PreEventTimers.leadTimes(from: settings))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(5 * 60 + 30)
        let event = makeEvent(id: "personal", title: "Errand", start: start, category: "Personal")

        let fires = await timers.upcomingFires(events: [event], now: now, window: 90)

        XCTAssertEqual(fires.map(\.leadMinutes), [5])
    }

    func testEmptyLeadArrayFallsBackToDefault() {
        var settings = AppSettings.default
        settings.leadTimes.exam = []
        XCTAssertEqual(PreEventTimers.leadTimes(from: settings)["exam"], [1440, 60])
    }

    // MARK: - A2-14 horizon and catch-up

    func testSeventyTwoHourLeadIsVisibleOnMondayForThursdayEvent() async {
        let monday = chicago.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 15, minute: 0, second: 0))!
        let thursday = chicago.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 15, minute: 0, second: 0))!
        let dates = PreEventTimers.queryDates(now: monday, leadMinutes: [4320], calendar: chicago)
        XCTAssertTrue(dates.contains { chicago.isDate($0, inSameDayAs: thursday) })

        let timers = PreEventTimers(leadTimesByCategory: ["internship_deadline": [4320]])
        let event = makeEvent(
            id: "intern", title: "Offer deadline", start: thursday,
            end: thursday.addingTimeInterval(3600), category: "internship_deadline")
        let fires = await timers.upcomingFires(events: [event], now: monday, window: 90)

        XCTAssertEqual(fires.map(\.leadMinutes), [4320])
        XCTAssertEqual(fires.first?.fireAt, monday)
    }

    func testCatchUpDeliversTwentyMinutesLateButNotTwoHoursLate() async {
        let monday = chicago.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 15, minute: 0, second: 0))!
        let thursday = chicago.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 15, minute: 0, second: 0))!
        let timers = PreEventTimers(leadTimesByCategory: ["internship_deadline": [4320]])
        let event = makeEvent(
            id: "intern", title: "Offer deadline", start: thursday,
            end: thursday.addingTimeInterval(3600), category: "internship_deadline")

        let twentyLate = await timers.upcomingFires(
            events: [event], now: monday.addingTimeInterval(20 * 60), window: 90)
        XCTAssertEqual(twentyLate.map(\.leadMinutes), [4320])

        let twoHoursLate = await timers.upcomingFires(
            events: [event], now: monday.addingTimeInterval(2 * 3600), window: 90)
        XCTAssertTrue(twoHoursLate.isEmpty)

        let morningOfEvent = chicago.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 8, minute: 0, second: 0))!
        let morning = await timers.upcomingFires(events: [event], now: morningOfEvent, window: 90)
        XCTAssertFalse(morning.contains { $0.leadMinutes == 4320 })
    }

    func testSpringForwardQueryIncludesSunday() {
        let saturday = chicago.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 30, second: 0))!
        let sunday = chicago.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12, minute: 0, second: 0))!
        let dates = PreEventTimers.queryDates(now: saturday, leadMinutes: [15], calendar: chicago)
        XCTAssertTrue(dates.contains { chicago.isDate($0, inSameDayAs: sunday) })
    }

    // MARK: - A2-16 risk spam

    func testSameRiskKeyUndismissedDoesNotNotify() {
        let now = Date()
        let previous = BriefingScheduler.RiskAlertPrevious(
            key: "clusteredDeadlines|t1|t2", dismissedAt: nil, presentOnPreviousScan: true)
        XCTAssertFalse(BriefingScheduler.shouldNotify(
            key: "clusteredDeadlines|t1|t2", previous: previous, now: now))
    }

    func testSameRiskKeyDismissedOneMinuteAgoDoesNotNotify() {
        let now = Date()
        let previous = BriefingScheduler.RiskAlertPrevious(
            key: "assignmentDueSoon|t1",
            dismissedAt: now.addingTimeInterval(-60),
            presentOnPreviousScan: true)
        XCTAssertFalse(BriefingScheduler.shouldNotify(
            key: "assignmentDueSoon|t1", previous: previous, now: now))
    }

    func testSameRiskKeyDismissedThirteenHoursAgoNotifiesWhileStillTrue() {
        let now = Date()
        let previous = BriefingScheduler.RiskAlertPrevious(
            key: "assignmentDueSoon|t1",
            dismissedAt: now.addingTimeInterval(-13 * 3600),
            presentOnPreviousScan: true)
        XCTAssertTrue(BriefingScheduler.shouldNotify(
            key: "assignmentDueSoon|t1", previous: previous, now: now))
    }

    func testRiskKeyThatGainedATaskIdNotifies() {
        let now = Date()
        let previous = BriefingScheduler.RiskAlertPrevious(
            key: "clusteredDeadlines|t1|t2", dismissedAt: nil, presentOnPreviousScan: true)
        XCTAssertTrue(BriefingScheduler.shouldNotify(
            key: "clusteredDeadlines|t1|t2|t3", previous: previous, now: now))
    }

    func testDismissedRiskNotifiesWhenItReturnsAfterAnAbsence() {
        let now = Date()
        let previous = BriefingScheduler.RiskAlertPrevious(
            key: "assignmentDueSoon|t1",
            dismissedAt: now.addingTimeInterval(-60),
            presentOnPreviousScan: false)
        XCTAssertTrue(BriefingScheduler.shouldNotify(
            key: "assignmentDueSoon|t1", previous: previous, now: now))
    }

    // MARK: - A2-20 timer reschedule

    func testChangingBriefingTimeReplacesArmedFire() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 7, minute: 0, second: 0))!
        let armed = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 8, minute: 0, second: 0))!
        let next = BriefingScheduler.reconcile(armed: armed, storedHour: 10, storedMinute: 0, now: now, calendar: cal)
        let expected = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 10, minute: 0, second: 0))!
        XCTAssertEqual(next, expected)
    }

    func testUnchangedBriefingTimeKeepsArmedTimer() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 7, minute: 0, second: 0))!
        let armed = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 8, minute: 0, second: 0))!
        XCTAssertNil(BriefingScheduler.reconcile(
            armed: armed, storedHour: 8, storedMinute: 0, now: now, calendar: cal))
    }

    func testStaleTimerGenerationDoesNotDeliver() {
        XCTAssertFalse(BriefingScheduler.shouldDeliver(firedGeneration: 1, currentGeneration: 2))
        XCTAssertTrue(BriefingScheduler.shouldDeliver(firedGeneration: 2, currentGeneration: 2))
    }

    private func makeEvent(id: String, title: String, start: Date, end: Date? = nil,
                           category: String, eventType: String? = nil) -> GCalEventCache {
        GCalEventCache(
            gcalEventId: id, calendarId: "primary", title: title,
            startAt: start, endAt: end ?? start.addingTimeInterval(3600),
            location: nil, category: category, lastSyncedAt: start, rawJson: "{}",
            eventType: eventType)
    }
}
