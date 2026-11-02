import Foundation
import AssistantShared
import AssistantStore

public actor BriefingScheduler {

    private let db: AssistantDB
    private let dispatcher: BriefingDispatcher
    private let composer: BriefingComposer
    private let rules: BriefingRules
    private let preEvent: PreEventTimers
    private let setting: SettingRepository

    private var morningTimer: DispatchSourceTimer?
    private var eveningTimer: DispatchSourceTimer?
    private var preEventTimer: DispatchSourceTimer?
    private var riskScanTimer: DispatchSourceTimer?
    private var morningFireAt: Date?
    private var eveningFireAt: Date?
    private var morningGeneration = 0
    private var eveningGeneration = 0
    private var clockObservers: [any NSObjectProtocol] = []
    /// Nil until the first risk scan finishes. An unknown history is not treated as an absence.
    private var riskKeysOnPreviousScan: Set<String>?

    public init(db: AssistantDB,
                dispatcher: BriefingDispatcher,
                composer: BriefingComposer,
                rules: BriefingRules,
                preEvent: PreEventTimers = PreEventTimers()) {
        self.db = db
        self.dispatcher = dispatcher
        self.composer = composer
        self.rules = rules
        self.preEvent = preEvent
        self.setting = SettingRepository(db: db)
    }

    public func start() async {
        await scheduleMorning()
        await scheduleEvening()
        await schedulePreEventLoop()
        await scheduleRiskScans()
        observeClockChanges()
    }

    public func stop() {
        morningGeneration += 1
        eveningGeneration += 1
        morningTimer?.cancel(); morningTimer = nil
        eveningTimer?.cancel(); eveningTimer = nil
        preEventTimer?.cancel(); preEventTimer = nil
        riskScanTimer?.cancel(); riskScanTimer = nil
        morningFireAt = nil
        eveningFireAt = nil
        for token in clockObservers {
            NotificationCenter.default.removeObserver(token)
        }
        clockObservers.removeAll()
    }

    // MARK: - Morning

    private func scheduleMorning() async {
        let now = Date()
        let (h, m) = await time(for: "morning_briefing_time", default: (8, 0))
        let fireAt = ScheduleCalendar.nextFire(after: now, hour: h, minute: m)
        armMorning(at: fireAt)
    }

    private func armMorning(at fireAt: Date) {
        morningTimer?.cancel()
        morningGeneration += 1
        let generation = morningGeneration
        morningFireAt = fireAt
        morningTimer = makeTimer(at: fireAt) { [weak self] in
            guard await self?.shouldDeliverMorning(generation) == true else { return }
            await self?.deliverMorning()
            await self?.scheduleMorning()  // next day
        }
    }

    private func shouldDeliverMorning(_ generation: Int) -> Bool {
        Self.shouldDeliver(firedGeneration: generation, currentGeneration: morningGeneration)
    }

    private func deliverMorning() async {
        do {
            let now = Date()
            let tasks = try TaskRepository(db: db).dueOn(date: now)
            let events = try GCalRepository(db: db).eventsOn(date: now)
            var items: [String] = events.map { "\(timeStr($0.startAt)) \($0.title)" }
            items.append(contentsOf: tasks.map { $0.title })
            let body = await composer.compose(morning: .init(items: items))
            let payload = BriefingPayload(
                id: UUID().uuidString, kindRaw: BriefingKind.morning.rawValue,
                title: "Morning briefing", body: body, firedAt: now,
                actionables: [.init(kind: .dismiss, label: "Got it", payload: nil)])
            try await dispatcher.deliver(payload)
        } catch {
            NSLog("[BriefingScheduler] morning error: \(error)")
        }
    }

    // MARK: - Evening

    private func scheduleEvening() async {
        let now = Date()
        let (h, m) = await time(for: "evening_briefing_time", default: (21, 0))
        let fireAt = ScheduleCalendar.nextFire(after: now, hour: h, minute: m)
        armEvening(at: fireAt)
    }

    private func armEvening(at fireAt: Date) {
        eveningTimer?.cancel()
        eveningGeneration += 1
        let generation = eveningGeneration
        eveningFireAt = fireAt
        eveningTimer = makeTimer(at: fireAt) { [weak self] in
            guard await self?.shouldDeliverEvening(generation) == true else { return }
            await self?.deliverEvening()
            await self?.scheduleEvening()
        }
    }

    private func shouldDeliverEvening(_ generation: Int) -> Bool {
        Self.shouldDeliver(firedGeneration: generation, currentGeneration: eveningGeneration)
    }

    private func deliverEvening() async {
        do {
            let now = Date()
            let cal = Calendar(identifier: .gregorian)
            let remaining = try TaskRepository(db: db).dueOn(date: now)
                .filter { $0.completedAt == nil }
                .map { $0.title }
            let tomorrow = try TaskRepository(db: db).dueOn(date: cal.date(byAdding: .day, value: 1, to: now)!).map { $0.title }
            let body = await composer.compose(evening: .init(remaining: remaining, tomorrow: tomorrow))
            let payload = BriefingPayload(
                id: UUID().uuidString, kindRaw: BriefingKind.evening.rawValue,
                title: "Wrap-up", body: body, firedAt: now,
                actionables: [.init(kind: .dismiss, label: "Goodnight", payload: nil)])
            try await dispatcher.deliver(payload)
        } catch {
            NSLog("[BriefingScheduler] evening error: \(error)")
        }
    }

    // MARK: - Pre-event

    /// Wakes every 60s, checks for the next fire across all cached events.
    private func schedulePreEventLoop() async {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 30, repeating: .seconds(60))
        t.setEventHandler { [weak self] in
            _Concurrency.Task.detached { await self?.checkPreEvent() }
        }
        t.resume()
        preEventTimer = t
    }

    private func checkPreEvent() async {
        do {
            await reconcileBriefingTimers()
            let now = Date()
            let settings: AppSettings = (try? setting.getCodable("app_settings")) ?? .default
            let leadMap = PreEventTimers.leadTimes(from: settings)
            let dates = PreEventTimers.queryDates(now: now, leadMinutes: leadMap.values.flatMap { $0 })
            let repo = GCalRepository(db: db)
            var seen = Set<String>()
            var events: [GCalEventCache] = []
            for day in dates {
                for event in try repo.eventsOn(date: day) where seen.insert(event.gcalEventId).inserted {
                    events.append(event)
                }
            }
            let fires = await preEvent.upcomingFires(events: events, now: now, window: 90, leadTimes: leadMap)
            for f in fires where f.fireAt <= now.addingTimeInterval(60) {
                await preEvent.markFired(eventId: f.eventId, leadMinutes: f.leadMinutes)
                let body = await composer.composePreEvent(title: f.title, minutesUntil: f.leadMinutes)
                let payload = BriefingPayload(
                    id: UUID().uuidString, kindRaw: BriefingKind.preEvent.rawValue,
                    title: f.title, body: body, firedAt: now,
                    actionables: [.init(kind: .openItem, label: "Open", payload: f.eventId),
                                  .init(kind: .dismiss, label: "Dismiss", payload: nil)])
                try await dispatcher.deliver(payload)
            }
        } catch {
            NSLog("[BriefingScheduler] preEvent error: \(error)")
        }
    }

    // MARK: - Risk scans

    /// Every 5 minutes — same cadence as GCal sync.
    private func scheduleRiskScans() async {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 60, repeating: .seconds(300))
        t.setEventHandler { [weak self] in
            _Concurrency.Task.detached { await self?.runRiskScans() }
        }
        t.resume()
        riskScanTimer = t
    }

    private func runRiskScans() async {
        do {
            let now = Date()
            let findings = try rules.evaluate()
            let recent = (try? BriefingRepository(db: db).recent(kind: BriefingKind.risk.rawValue, limit: 50)) ?? []
            let history = Self.latestRiskNotices(in: recent)
            var keysThisScan = Set<String>()
            for f in findings {
                let key = Self.riskKey(kind: f.kind.rawValue, payloadJSON: f.payloadJSON)
                keysThisScan.insert(key)
                let presentOnPreviousScan = riskKeysOnPreviousScan?.contains(key) ?? true
                let previous = history[key].map {
                    RiskAlertPrevious(key: key, dismissedAt: $0.dismissedAt,
                                      presentOnPreviousScan: presentOnPreviousScan)
                }
                guard Self.shouldNotify(key: key, previous: previous, now: now) else { continue }
                let body = await composer.composeRisk(finding: f)
                let payload = BriefingPayload(
                    id: UUID().uuidString, kindRaw: BriefingKind.risk.rawValue,
                    title: f.kind.rawValue, body: body, firedAt: now,
                    actionables: [.init(kind: .dismiss, label: "Dismiss", payload: key)])
                try await dispatcher.deliver(payload)
            }
            riskKeysOnPreviousScan = keysThisScan
        } catch {
            NSLog("[BriefingScheduler] risk error: \(error)")
        }
    }

    // MARK: - Helpers

    /// Re-read saved clock times. Nil means the armed fire date still matches.
    /// A timer whose clock time is unchanged is left alone, including when `now` has
    /// just passed it, so a settings check does not cancel the in-flight delivery.
    public static func reconcile(armed: Date, storedHour: Int, storedMinute: Int, now: Date,
                                 calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        let next = ScheduleCalendar.nextFire(after: now, hour: storedHour, minute: storedMinute, calendar: calendar)
        if calendar.isDate(next, equalTo: armed, toGranularity: .minute) { return nil }
        let sameClock = calendar.component(.hour, from: armed) == storedHour
            && calendar.component(.minute, from: armed) == storedMinute
        if sameClock {
            if armed > now { return nil }
            if calendar.isDate(armed, inSameDayAs: now) { return nil }
        }
        return next
    }

    public static func shouldDeliver(firedGeneration: Int, currentGeneration: Int) -> Bool {
        firedGeneration == currentGeneration
    }

    /// Previous risk alert for one key. `presentOnPreviousScan` is false after the finding
    /// was absent for a full scan and has now returned.
    public struct RiskAlertPrevious: Equatable, Sendable {
        public let key: String
        public let dismissedAt: Date?
        public let presentOnPreviousScan: Bool

        public init(key: String, dismissedAt: Date?, presentOnPreviousScan: Bool) {
            self.key = key
            self.dismissedAt = dismissedAt
            self.presentOnPreviousScan = presentOnPreviousScan
        }
    }

    /// Notify on a new key. Suppress an undismissed row. After dismissal, notify again at
    /// the earlier of "absent for one scan, then back" or 12 hours after `dismissedAt`.
    public static func shouldNotify(key: String, previous: RiskAlertPrevious?, now: Date) -> Bool {
        guard let previous else { return true }
        guard previous.key == key else { return true }
        guard let dismissedAt = previous.dismissedAt else { return false }
        if !previous.presentOnPreviousScan { return true }
        return now.timeIntervalSince(dismissedAt) >= 12 * 3600
    }

    private func time(for key: String, default fallback: (Int, Int)) async -> (Int, Int) {
        struct HM: Codable { let hour: Int; let minute: Int }
        if let hm: HM = try? setting.getCodable(key) { return (hm.hour, hm.minute) }
        return fallback
    }

    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func reconcileBriefingTimers(now: Date = Date()) async {
        let (mh, mm) = await time(for: "morning_briefing_time", default: (8, 0))
        if let armed = morningFireAt,
           let replacement = Self.reconcile(armed: armed, storedHour: mh, storedMinute: mm, now: now) {
            armMorning(at: replacement)
        }
        let (eh, em) = await time(for: "evening_briefing_time", default: (21, 0))
        if let armed = eveningFireAt,
           let replacement = Self.reconcile(armed: armed, storedHour: eh, storedMinute: em, now: now) {
            armEvening(at: replacement)
        }
    }

    private func observeClockChanges() {
        guard clockObservers.isEmpty else { return }
        let names: [Notification.Name] = [.NSSystemTimeZoneDidChange, .NSSystemClockDidChange]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: nil
            ) { [weak self] _ in
                _Concurrency.Task { await self?.reconcileBriefingTimers() }
            }
            clockObservers.append(token)
        }
    }

    private struct StoredRiskNotice {
        var dismissedAt: Date?
    }

    /// Kind plus sorted task ids. Clustered deadlines fall back to the sorted title list
    /// when the payload has no task ids.
    static func riskKey(kind: String, payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return kind
        }
        let parts: [String]
        if kind == RiskFinding.Kind.clusteredDeadlines.rawValue {
            let taskIDs = object["task_ids"] as? [String] ?? []
            parts = taskIDs.isEmpty ? ((object["titles"] as? [String]) ?? []).sorted() : taskIDs.sorted()
        } else {
            var ids: [String] = []
            if let id = object["task_id"] as? String { ids.append(id) }
            if let many = object["task_ids"] as? [String] { ids.append(contentsOf: many) }
            parts = ids.sorted()
        }
        return ([kind] + parts).joined(separator: "|")
    }

    private static func storedRiskKey(_ payloadJSON: String) -> String? {
        guard let data = payloadJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BriefingPayload.self, from: data),
              let key = payload.actionables.first(where: { $0.kind == .dismiss })?.payload,
              !key.isEmpty else { return nil }
        return key
    }

    private static func latestRiskNotices(in rows: [Briefing]) -> [String: StoredRiskNotice] {
        var notices: [String: StoredRiskNotice] = [:]
        for row in rows {
            guard let key = storedRiskKey(row.payloadJson), notices[key] == nil else { continue }
            notices[key] = StoredRiskNotice(dismissedAt: row.dismissedAt)
        }
        return notices
    }

    private func makeTimer(at fireAt: Date, action: @escaping () async -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        let delay = max(0, fireAt.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { _Concurrency.Task.detached { await action() } }
        timer.resume()
        return timer
    }
}
