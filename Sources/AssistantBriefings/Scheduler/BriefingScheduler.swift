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
    }

    public func stop() {
        morningTimer?.cancel(); morningTimer = nil
        eveningTimer?.cancel(); eveningTimer = nil
        preEventTimer?.cancel(); preEventTimer = nil
        riskScanTimer?.cancel(); riskScanTimer = nil
    }

    // MARK: - Morning

    private func scheduleMorning() async {
        let now = Date()
        let (h, m) = await time(for: "morning_briefing_time", default: (8, 0))
        let fireAt = ScheduleCalendar.nextFire(after: now, hour: h, minute: m)
        morningTimer = makeTimer(at: fireAt) { [weak self] in
            await self?.deliverMorning()
            await self?.scheduleMorning()  // next day
        }
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
        eveningTimer = makeTimer(at: fireAt) { [weak self] in
            await self?.deliverEvening()
            await self?.scheduleEvening()
        }
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
            let now = Date()
            let events = try GCalRepository(db: db).eventsOn(date: now)
                + (try GCalRepository(db: db).eventsOn(date: now.addingTimeInterval(86_400)))
            let fires = await preEvent.upcomingFires(events: events, now: now, window: 90)
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
            let findings = try rules.evaluate()
            for f in findings {
                let body = await composer.composeRisk(finding: f)
                let payload = BriefingPayload(
                    id: UUID().uuidString, kindRaw: BriefingKind.risk.rawValue,
                    title: f.kind.rawValue, body: body, firedAt: Date(),
                    actionables: [.init(kind: .dismiss, label: "Dismiss", payload: nil)])
                try await dispatcher.deliver(payload)
            }
        } catch {
            NSLog("[BriefingScheduler] risk error: \(error)")
        }
    }

    // MARK: - Helpers

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

    private func makeTimer(at fireAt: Date, action: @escaping () async -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        let delay = max(0, fireAt.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { _Concurrency.Task.detached { await action() } }
        timer.resume()
        return timer
    }
}
