import Foundation

@objc(AssistantEventsProtocol)
public protocol AssistantEventsProtocol {
    /// Daemon → UI: a briefing is ready to display. `data` decodes to BriefingPayload.
    func briefingReady(_ data: Data, reply: @escaping (Bool) -> Void)
}
