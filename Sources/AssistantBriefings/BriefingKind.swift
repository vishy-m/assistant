import Foundation

public enum BriefingKind: String, Codable, Equatable {
    case morning
    case evening
    case preEvent = "pre_event"
    case risk
}
