import Foundation

public struct BriefingPayload: Codable, Equatable {
    public let id: String
    public let kindRaw: String           // BriefingKind raw
    public let title: String
    public let body: String
    public let firedAt: Date
    public let actionables: [Actionable]

    public struct Actionable: Codable, Equatable {
        public enum Kind: String, Codable {
            case markDone
            case blockTime
            case snoozeOneHour
            case dismiss
            case openItem
        }
        public let kind: Kind
        public let label: String
        public let payload: String?      // arbitrary string (e.g., task id, event id)

        public init(kind: Kind, label: String, payload: String?) {
            self.kind = kind
            self.label = label
            self.payload = payload
        }
    }

    public init(id: String, kindRaw: String, title: String, body: String,
                firedAt: Date, actionables: [Actionable]) {
        self.id = id
        self.kindRaw = kindRaw
        self.title = title
        self.body = body
        self.firedAt = firedAt
        self.actionables = actionables
    }
}
