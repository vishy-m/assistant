import Foundation
import AssistantShared
import AssistantStore

public actor BriefingDispatcher {

    public typealias PushFn = @Sendable (BriefingPayload) -> Bool

    private let db: AssistantDB
    private let isFocused: @Sendable () -> Bool
    private let pushToUI: PushFn
    private let repo: BriefingRepository

    public init(db: AssistantDB,
                isFocused: @escaping @Sendable () -> Bool,
                pushToUI: @escaping PushFn) {
        self.db = db
        self.isFocused = isFocused
        self.pushToUI = pushToUI
        self.repo = BriefingRepository(db: db)
    }

    public func deliver(_ payload: BriefingPayload) async throws {
        let payloadData = try JSONEncoder().encode(payload)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
        let logEntry = Briefing(
            id: payload.id,
            kind: payload.kindRaw,
            firedAt: payload.firedAt,
            payloadJson: payloadJSON,
            dismissedAt: nil,
            actedOn: false)
        try repo.insert(logEntry)

        if isFocused() {
            // Queued: dismissed_at stays nil; drainQueue picks it up later.
            return
        }
        _ = pushToUI(payload)
    }

    /// Called when Focus ends or the scheduler wakes up.
    public func drainQueue(since: Date) async throws {
        let pending = try repo.pendingDelivery(since: since)
        for entry in pending {
            guard let data = entry.payloadJson.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BriefingPayload.self, from: data) else {
                continue
            }
            _ = pushToUI(payload)
        }
    }
}
