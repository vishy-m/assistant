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
            let weight = cat.weightPct.isFinite ? cat.weightPct : 0

            // CURRENT — items with no usable score are left out, not scored as NaN.
            let gradedCurrent = catItems.filter { isScored($0) }
            let droppedCurrent = dropExtremes(gradedCurrent,
                                              lowestN: cat.dropLowestN, highestN: cat.dropHighestN)
            let currentPct = average(items: droppedCurrent.kept)

            // PROJECTED
            let projectedResolved = projectedItems(catItems, projection: input.projection).items
                .filter { isScored($0) }
            let droppedProjected = dropExtremes(projectedResolved,
                                                lowestN: cat.dropLowestN, highestN: cat.dropHighestN)
            let projectedPct = average(items: droppedProjected.kept)

            categoryRows.append(.init(
                categoryId: cat.id, categoryName: cat.name,
                weightPct: weight,
                currentPct: currentPct, projectedPct: projectedPct,
                droppedItemIds: droppedCurrent.dropped))

            if cat.weightPct.isFinite {
                if !droppedCurrent.kept.isEmpty {
                    let contribution = currentPct * cat.weightPct
                    if contribution.isFinite {
                        weightedCurrent += contribution
                        weightSumUsedCurrent += cat.weightPct
                    }
                }
                if !droppedProjected.kept.isEmpty {
                    let contribution = projectedPct * cat.weightPct
                    if contribution.isFinite {
                        weightedProjected += contribution
                        weightSumUsedProjected += cat.weightPct
                    }
                }
            }
        }

        // A regular item with no category does not dilute a weighted course.
        // When it is the only scored work, the course percent is that work's
        // mean so the course is not reported as 0.
        let uncategorized = input.items.filter { $0.categoryId == nil && !$0.isExtraCredit }
        let uncatCurrent = uncategorized.filter { isScored($0) }
        let uncatProjected = projectedItems(uncategorized, projection: input.projection).items
            .filter { isScored($0) }

        var currentPct = weightSumUsedCurrent > 0 ? weightedCurrent / weightSumUsedCurrent : 0
        if weightSumUsedCurrent == 0, !uncatCurrent.isEmpty {
            currentPct = average(items: uncatCurrent)
        }
        var projectedPct = weightSumUsedProjected > 0 ? weightedProjected / weightSumUsedProjected : 0
        if weightSumUsedProjected == 0, !uncatProjected.isEmpty {
            projectedPct = average(items: uncatProjected)
        }

        let extraCreditEarned = input.items
            .filter(\.isExtraCredit)
            .compactMap { finiteOrNil($0.earnedPoints) }
            .reduce(0.0, +)
        let extraCreditProjected = input.items
            .filter(\.isExtraCredit)
            .compactMap { item -> Double? in
                finiteOrNil(item.earnedPoints ?? input.projection[item.id] ?? 0)
            }
            .reduce(0.0, +)

        let safetyCap = 20.0
        let finalCurrent = finite(min(finite(currentPct) + min(extraCreditEarned, safetyCap), 110.0))
        let finalProjected = finite(min(finite(projectedPct) + min(extraCreditProjected, safetyCap), 110.0))

        return GradeBreakdown(
            currentPct: finalCurrent,
            projectedPct: finalProjected,
            perCategory: categoryRows,
            currentLetter: gradingScale.letter(for: finalCurrent),
            projectedLetter: gradingScale.letter(for: finalProjected))
    }

    /// A usable score has finite earned points, a positive finite max, and no
    /// non-finite weight override. Anything else is treated as unscored.
    private static func isScored(_ item: GradeCalculatorInput.ItemIn) -> Bool {
        guard let earned = item.earnedPoints, earned.isFinite else { return false }
        guard item.maxPoints.isFinite, item.maxPoints > 0 else { return false }
        if let override = item.weightOverridePct, !override.isFinite { return false }
        return true
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func finiteOrNil(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
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
        guard isScored(item), let earned = item.earnedPoints else { return 0 }
        return earned / item.maxPoints
    }

    /// Equal mean when every kept item has no override. Otherwise a weighted
    /// mean: each override is its weight (negatives count as 0) and items with
    /// no override share whatever is left of 100. A zero weight total is 0.
    private static func average(items: [GradeCalculatorInput.ItemIn]) -> Double {
        struct Scored {
            var percent: Double
            var override: Double?
        }
        var rows: [Scored] = []
        for item in items {
            guard isScored(item), let earned = item.earnedPoints else { continue }
            let percent = (earned / item.maxPoints) * 100
            guard percent.isFinite else { continue }
            rows.append(Scored(percent: percent, override: item.weightOverridePct))
        }
        guard !rows.isEmpty else { return 0 }

        if rows.allSatisfy({ $0.override == nil }) {
            let mean = rows.reduce(0.0) { $0 + $1.percent } / Double(rows.count)
            return mean.isFinite ? mean : 0
        }

        let overrideSum = rows.reduce(0.0) { partial, row in
            guard let override = row.override else { return partial }
            return partial + max(0, override)
        }
        let openItems = rows.filter { $0.override == nil }
        let remainder = max(0, 100 - overrideSum)
        let nilShare = openItems.isEmpty ? 0 : remainder / Double(openItems.count)

        var weighted = 0.0
        var weightSum = 0.0
        for row in rows {
            let weight = row.override.map { max(0, $0) } ?? (nilShare.isFinite ? nilShare : 0)
            weighted += row.percent * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return 0 }
        let mean = weighted / weightSum
        return mean.isFinite ? mean : 0
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
