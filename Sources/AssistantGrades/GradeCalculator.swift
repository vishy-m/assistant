import Foundation

public struct GradeBreakdown: Equatable, Codable {

    public struct CategoryBreakdown: Equatable, Codable {
        public let categoryId: String
        public let categoryName: String
        public let weightPct: Double
        public let currentPct: Double
        public let projectedPct: Double
        public let droppedItemIds: [String]
    }

    public let currentPct: Double
    public let projectedPct: Double
    public let perCategory: [CategoryBreakdown]
    public let currentLetter: String
    public let projectedLetter: String
}

public enum GradeCalculator {

    public static func compute(input: GradeCalculatorInput,
                               gradingScale: GradingScale = .default) -> GradeBreakdown {

        var categoryRows: [GradeBreakdown.CategoryBreakdown] = []
        var weightedCurrent: Double = 0
        var weightedProjected: Double = 0
        var weightSumUsedCurrent: Double = 0
        var weightSumUsedProjected: Double = 0

        for cat in input.categories {
            let catItems = input.items.filter { $0.categoryId == cat.id && !$0.isExtraCredit }
            // CURRENT — only graded
            let gradedCurrent = catItems.filter { $0.earnedPoints != nil }
            let currentPct = average(items: gradedCurrent, projection: [:])
            // PROJECTED
            let projected = projectedItems(catItems, projection: input.projection)
            let projectedPct = average(items: projected.items, projection: [:])

            categoryRows.append(.init(
                categoryId: cat.id,
                categoryName: cat.name,
                weightPct: cat.weightPct,
                currentPct: currentPct,
                projectedPct: projectedPct,
                droppedItemIds: []))

            if !gradedCurrent.isEmpty {
                weightedCurrent += currentPct * cat.weightPct
                weightSumUsedCurrent += cat.weightPct
            }
            if !catItems.isEmpty {
                weightedProjected += projectedPct * cat.weightPct
                weightSumUsedProjected += cat.weightPct
            }
        }

        let currentPct = weightSumUsedCurrent > 0 ? weightedCurrent / weightSumUsedCurrent : 0
        let projectedPct = weightSumUsedProjected > 0 ? weightedProjected / weightSumUsedProjected : 0

        return GradeBreakdown(
            currentPct: currentPct,
            projectedPct: projectedPct,
            perCategory: categoryRows,
            currentLetter: gradingScale.letter(for: currentPct),
            projectedLetter: gradingScale.letter(for: projectedPct))
    }

    private static func average(items: [GradeCalculatorInput.ItemIn],
                                projection: [String: Double]) -> Double {
        guard !items.isEmpty else { return 0 }
        var sumRatios = 0.0
        var count = 0.0
        for i in items {
            let pts = i.earnedPoints ?? projection[i.id]
            guard let earned = pts else { continue }
            sumRatios += (earned / i.maxPoints) * 100
            count += 1
        }
        return count == 0 ? 0 : sumRatios / count
    }

    /// Substitutes ungraded items with projection value (or 100 as default).
    private static func projectedItems(_ items: [GradeCalculatorInput.ItemIn],
                                        projection: [String: Double]) -> (items: [GradeCalculatorInput.ItemIn], substituted: [String]) {
        var substituted: [String] = []
        let resolved = items.map { item -> GradeCalculatorInput.ItemIn in
            if item.earnedPoints != nil { return item }
            substituted.append(item.id)
            let hypothetical = projection[item.id] ?? item.maxPoints  // default = 100%
            return GradeCalculatorInput.ItemIn(
                id: item.id, categoryId: item.categoryId,
                maxPoints: item.maxPoints, earnedPoints: hypothetical,
                isExtraCredit: item.isExtraCredit,
                weightOverridePct: item.weightOverridePct)
        }
        return (resolved, substituted)
    }
}
