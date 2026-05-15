import Foundation

public struct GradeCalculatorInput: Equatable, Codable {

    public struct CategoryIn: Equatable, Codable {
        public let id: String
        public let name: String
        public let weightPct: Double
        public let dropLowestN: Int
        public let dropHighestN: Int

        public init(id: String, name: String, weightPct: Double,
                    dropLowestN: Int, dropHighestN: Int) {
            self.id = id
            self.name = name
            self.weightPct = weightPct
            self.dropLowestN = dropLowestN
            self.dropHighestN = dropHighestN
        }
    }

    public struct ItemIn: Equatable, Codable {
        public let id: String
        public let categoryId: String?
        public let maxPoints: Double
        public let earnedPoints: Double?     // nil = ungraded
        public let isExtraCredit: Bool
        public let weightOverridePct: Double?

        public init(id: String, categoryId: String?, maxPoints: Double,
                    earnedPoints: Double?, isExtraCredit: Bool,
                    weightOverridePct: Double?) {
            self.id = id
            self.categoryId = categoryId
            self.maxPoints = maxPoints
            self.earnedPoints = earnedPoints
            self.isExtraCredit = isExtraCredit
            self.weightOverridePct = weightOverridePct
        }
    }

    public let categories: [CategoryIn]
    public let items: [ItemIn]
    /// Hypothetical earned values for ungraded items, keyed by item id.
    public let projection: [String: Double]

    public init(categories: [CategoryIn],
                items: [ItemIn],
                projection: [String: Double] = [:]) {
        self.categories = categories
        self.items = items
        self.projection = projection
    }
}
