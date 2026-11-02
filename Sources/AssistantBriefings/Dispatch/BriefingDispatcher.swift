import Foundation
import AssistantShared
import AssistantStore

public actor BriefingDispatcher {

    /// Pushes to the UI and returns true only once the UI acknowledged it.
    public typealias PushFn = @Sendable (BriefingPayload) async -> Bool

    private let db: AssistantDB
    private let isFocused: @Sendable () -> Bool
    private let pushToUI: PushFn
    private let repo: BriefingRepository
    /// Ids being pushed right now. The actor is re-entrant across the
    /// `await pushToUI`, so this stops two drains sending the same card.
    private var inFlight: Set<String> = []

    /// - Parameter isFocused: true while delivery should be held back
    ///   (Focus on, or Focus state not yet known).
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
            // Queued: no delivery row; drainQueue picks it up later.
            return
        }
        try await push(payload)
    }

    /// Re-sends briefings the UI never acknowledged. Called when the UI
    /// (re)registers and when Focus ends.
    public func drainQueue(since: Date) async throws {
        guard !isFocused() else { return }
        let pending = try repo.undelivered(since: since)
        for entry in pending {
            guard let data = entry.payloadJson.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BriefingPayload.self, from: data) else {
                continue
            }
            try await push(payload)
        }
    }

    private func push(_ payload: BriefingPayload) async throws {
        guard !inFlight.contains(payload.id) else { return }
        inFlight.insert(payload.id)
        defer { inFlight.remove(payload.id) }
        if await pushToUI(payload) {
            try repo.markDelivered(id: payload.id)
        }
    }
}
