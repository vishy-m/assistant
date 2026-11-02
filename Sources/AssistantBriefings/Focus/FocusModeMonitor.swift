import Foundation
#if canImport(Intents)
import Intents
#endif

/// Focus status as the briefing dispatcher sees it.
///
/// The daemon is a LaunchAgent and can't be granted Focus access itself, so
/// the UI app requests authorization, reads the status, and relays it over
/// XPC (`setFocusStatus`). Until the UI reports, the state is `unknown`.
public enum FocusState: String, Sendable, Equatable {
    /// The UI hasn't reported, or the system status is unavailable.
    case unknown
    /// The user denied Focus access. Focus can't be honoured, so deliver.
    case denied
    case focused
    case notFocused

    public static func reduce(authorized: Bool, isFocused: Bool?) -> FocusState {
        guard authorized else { return .denied }
        switch isFocused {
        case .some(true): return .focused
        case .some(false): return .notFocused
        case .none: return .unknown
        }
    }

    /// `unknown` queues like Focus-on; the queue is drained once the UI
    /// reports a deliverable state.
    public var suppressesDelivery: Bool {
        self == .unknown || self == .focused
    }
}

/// Latest Focus state relayed by the UI. Thread-safe.
public final class FocusStatusStore: @unchecked Sendable {
    public static let shared = FocusStatusStore()

    private let lock = NSLock()
    private var _state: FocusState = .unknown

    public init() {}

    public var state: FocusState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// Records a relayed reading. Returns true when delivery just became
    /// possible (suppressing → not suppressing), i.e. the caller should drain.
    @discardableResult
    public func update(authorized: Bool, isFocused: Bool?) -> Bool {
        let new = FocusState.reduce(authorized: authorized, isFocused: isFocused)
        lock.lock(); defer { lock.unlock() }
        let opened = _state.suppressesDelivery && !new.suppressesDelivery
        _state = new
        return opened
    }
}

public struct FocusModeMonitor: Sendable {

    public init() {}

    /// Reads this process's Focus status. Only meaningful in a process that
    /// has been granted Focus authorization (the UI app); nil when unknown.
    public var isFocused: Bool? {
        #if canImport(Intents)
        if #available(macOS 13.0, *) {
            guard INFocusStatusCenter.default.authorizationStatus == .authorized else { return nil }
            return INFocusStatusCenter.default.focusStatus.isFocused
        }
        #endif
        return nil
    }

    /// Request the user's authorization to read focus status. Call from the
    /// UI app, not the LaunchAgent.
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
