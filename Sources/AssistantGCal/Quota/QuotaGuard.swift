import Foundation
import AssistantStore

/// Daily soft cap on GCal API calls. Counter persisted in the `setting` table.
public final class QuotaGuard {

    public static let defaultCap = 10_000

    private let setting: SettingRepository
    private let cap: Int
    private let clock: @Sendable () -> Date

    public init(db: AssistantDB, cap: Int = QuotaGuard.defaultCap,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.setting = SettingRepository(db: db)
        self.cap = cap
        self.clock = clock
    }

    struct DailyCounter: Codable {
        var dayKey: String   // YYYY-MM-DD
        var count: Int
    }

    private static let key = "gcal_quota_counter"

    private func dayKey(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    public func usedToday() throws -> Int {
        let today = dayKey(clock())
        let counter: DailyCounter? = try setting.getCodable(Self.key)
        return counter?.dayKey == today ? counter?.count ?? 0 : 0
    }

    /// Returns `true` if a call is permitted; consumes one unit if so.
    public func tryConsume() throws -> Bool {
        let today = dayKey(clock())
        var counter: DailyCounter = (try setting.getCodable(Self.key)) ?? DailyCounter(dayKey: today, count: 0)
        if counter.dayKey != today {
            counter = DailyCounter(dayKey: today, count: 0)
        }
        if counter.count >= cap { return false }
        counter.count += 1
        try setting.setCodable(Self.key, value: counter)
        return true
    }
}
