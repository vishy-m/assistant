import Foundation

public struct RiskFinding: Equatable {
    public enum Kind: String, Codable, Equatable {
        case clusteredDeadlines
        case gradeBelowTarget
        case assignmentDueSoon
        case opportunityHighFit       // Phase 3
    }

    public let kind: Kind
    public let summary: String
    public let payloadJSON: String

    public init(kind: Kind, summary: String, payloadJSON: String) {
        self.kind = kind
        self.summary = summary
        self.payloadJSON = payloadJSON
    }
}
