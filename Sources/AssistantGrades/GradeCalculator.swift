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

            // CURRENT
            let gradedCurrent = catItems.filter { $0.earnedPoints != nil }
            let droppedCurrent = dropExtremes(gradedCurrent,
                                              lowestN: cat.dropLowestN, highestN: cat.dropHighestN)
            let currentPct = average(items: droppedCurrent.kept, projection: [:])

            // PROJECTED
            let projectedResolved = projectedItems(catItems, projection: input.projection).items
            let droppedProjected = dropExtremes(projectedResolved,
                                                lowestN: cat.dropLowestN, highestN: cat.dropHighestN)
            let projectedPct = average(items: droppedProjected.kept, projection: [:])

            categoryRows.append(.init(
                categoryId: cat.id, categoryName: cat.name,
                weightPct: cat.weightPct,
                currentPct: currentPct, projectedPct: projectedPct,
                droppedItemIds: droppedCurrent.dropped))

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

        // Extra credit additions (graded EC items)
        let extraCreditEarned = input.items
            .filter { $0.isExtraCredit && $0.earnedPoints != nil }
            .reduce(0.0) { $0 + ($1.earnedPoints ?? 0) }
        let extraCreditProjected = input.items
            .filter { $0.isExtraCredit }
            .reduce(0.0) { acc, item in
                acc + (item.earnedPoints ?? input.projection[item.id] ?? 0)
            }

        let safetyCap = 20.0
        let finalCurrent = min(currentPct + min(extraCreditEarned, safetyCap), 110.0)
        let finalProjected = min(projectedPct + min(extraCreditProjected, safetyCap), 110.0)

        return GradeBreakdown(
            currentPct: finalCurrent,
            projectedPct: finalProjected,
            perCategory: categoryRows,
            currentLetter: gradingScale.letter(for: finalCurrent),
            projectedLetter: gradingScale.letter(for: finalProjected))
    }

    private static func dropExtremes(_ items: [GradeCalculatorInput.ItemIn],
                                     lowestN: Int, highestN: Int) -> (kept: [GradeCalculatorInput.ItemIn], dropped: [String]) {
        guard items.count > 1 else { return (items, []) }
        let sorted = items.sorted { ratio($0) < ratio($1) }
        let dropLow = max(0, min(lowestN, sorted.count - 1))
        let remainingAfterLow = Array(sorted.dropFirst(dropLow))
        let dropHigh = max(0, min(highestN, remainingAfterLow.count - 1))
        let kept = Array(remainingAfterLow.dropLast(dropHigh))
        let dropped = items.filter { item in !kept.contains(where: { $0.id == item.id }) }
                          .map(\.id)
        return (kept, dropped)
    }

    private static func ratio(_ item: GradeCalculatorInput.ItemIn) -> Double {
        guard let earned = item.earnedPoints else { return 0 }
        return earned / item.maxPoints
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
