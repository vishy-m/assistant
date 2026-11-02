import Foundation

/// Whether a calendar editor may close after a create reply.
public enum CalendarWriteGate {
    /// Any error keeps the editor open. A recurring create succeeds with a nil
    /// `event` on purpose (the master id is never surfaced), so for it a nil
    /// error is enough; a single create must also return the event.
    public static func shouldClose(errorMessage: String?, event: WeekEvent?,
                                   isRecurring: Bool) -> Bool {
        guard errorMessage == nil else { return false }
        return isRecurring || event != nil
    }

    public static func shouldClose(_ result: CalendarWriteResult, isRecurring: Bool) -> Bool {
        shouldClose(errorMessage: result.errorMessage, event: result.event,
                    isRecurring: isRecurring)
    }

    /// Message to show when the editor stays open.
    public static func failureMessage(_ result: CalendarWriteResult) -> String {
        result.errorMessage ?? "The event could not be created."
    }
}
