import AppKit
import AssistantShared

@MainActor
final class BriefingHandler {

    static let shared = BriefingHandler()
    private init() {}

    func handle(_ payload: BriefingPayload) {
        OverlayController.shared.summonWithBriefing(payload)
    }
}
