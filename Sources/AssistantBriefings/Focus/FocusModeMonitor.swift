import Foundation
#if canImport(Intents)
import Intents
#endif

public struct FocusModeMonitor: Sendable {

    public init() {}

    /// Returns true if the user is currently in any Focus / DnD mode that suppresses notifications.
    /// Falls back to false if entitlement isn't granted.
    public var isFocused: Bool {
        #if canImport(Intents)
        if #available(macOS 13.0, *) {
            return INFocusStatusCenter.default.focusStatus.isFocused ?? false
        }
        #endif
        return false
    }

    /// Request the user's authorization to read focus status. Call once at app start.
    public func requestAuthorizationIfNeeded() async {
        #if canImport(Intents)
        if #available(macOS 13.0, *) {
            if INFocusStatusCenter.default.authorizationStatus == .notDetermined {
                _ = await INFocusStatusCenter.default.requestAuthorization()
            }
        }
        #endif
    }
}
