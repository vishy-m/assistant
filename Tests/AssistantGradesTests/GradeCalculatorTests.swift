import XCTest
@testable import AssistantGrades

final class GradeCalculatorTests: XCTestCase {

    typealias Cat = GradeCalculatorInput.CategoryIn
    typealias Item = GradeCalculatorInput.ItemIn

    func testCurrentWeightedAverage() {
        let input = GradeCalculatorInput(
            categories: [
                Cat(id: "hw", name: "Homework", weightPct: 50, dropLowestN: 0, dropHighestN: 0),
                Cat(id: "ex", name: "Exams",    weightPct: 50, dropLowestN: 0, dropHighestN: 0)
            ],
            items: [
                Item(id: "hw1", categoryId: "hw", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "hw2", categoryId: "hw", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "mid", categoryId: "ex", maxPoints: 100, earnedPoints: 90,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        let result = GradeCalculator.compute(input: input)
        XCTAssertEqual(result.currentPct, 90, accuracy: 0.001)
    }

    func testIgnoresUngraded() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "i2", categoryId: "c", maxPoints: 100, earnedPoints: nil,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 80, accuracy: 0.001)
    }

    func testEmptyInputReturnsZero() {
        let r = GradeCalculator.compute(input: GradeCalculatorInput(categories: [], items: []))
        XCTAssertEqual(r.currentPct, 0)
    }

    func testDropLowestOne() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "hw", name: "HW", weightPct: 100, dropLowestN: 1, dropHighestN: 0)],
            items: [
                Item(id: "hw1", categoryId: "hw", maxPoints: 100, earnedPoints: 60,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "hw2", categoryId: "hw", maxPoints: 100, earnedPoints: 90,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "hw3", categoryId: "hw", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        // After dropping the 60: average of 90 and 100 = 95
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 95, accuracy: 0.001)
    }

    func testDropMoreThanGradedKeepsAll() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 5, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 80, accuracy: 0.001)
    }

    func testDropAppliesToProjectedToo() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 1, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 70,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "i2", categoryId: "c", maxPoints: 100, earnedPoints: nil,
                     isExtraCredit: false, weightOverridePct: nil)
            ],
            projection: ["i2": 100])
        // Projected: drop lowest (70) leaves 100 → 100%
        XCTAssertEqual(GradeCalculator.compute(input: input).projectedPct, 100, accuracy: 0.001)
    }

    func testExtraCreditAddsToFinal() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "xc", categoryId: nil, maxPoints: 5, earnedPoints: 5,
                     isExtraCredit: true, weightOverridePct: nil)
            ])
        // 80 base + 5 EC = 85
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 85, accuracy: 0.001)
    }

    func testExtraCreditNotDropped() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 1, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 60,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "i2", categoryId: "c", maxPoints: 100, earnedPoints: 90,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "xc", categoryId: "c", maxPoints: 5, earnedPoints: 5,
                     isExtraCredit: true, weightOverridePct: nil)
            ])
        // Drops lowest of non-EC (60), keeps 90; +5 EC = 95
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 95, accuracy: 0.001)
    }

    func testProjectionDefaultIs100() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "i2", categoryId: "c", maxPoints: 100, earnedPoints: nil,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).projectedPct, 90, accuracy: 0.001)
    }

    func testProjectionUsesOverride() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "i2", categoryId: "c", maxPoints: 100, earnedPoints: nil,
                     isExtraCredit: false, weightOverridePct: nil)
            ],
            projection: ["i2": 70])
        XCTAssertEqual(GradeCalculator.compute(input: input).projectedPct, 75, accuracy: 0.001)
    }

    func testZeroMaxPointsStayFiniteAndEncodable() throws {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "z", categoryId: "c", maxPoints: 0, earnedPoints: 0,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "i", categoryId: "c", maxPoints: 0, earnedPoints: 5,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        let result = GradeCalculator.compute(input: input)
        XCTAssertTrue(result.currentPct.isFinite)
        XCTAssertTrue(result.projectedPct.isFinite)
        XCTAssertTrue(result.perCategory.allSatisfy {
            $0.currentPct.isFinite && $0.projectedPct.isFinite && $0.weightPct.isFinite
        })
        XCTAssertNoThrow(try JSONEncoder().encode(result))
    }

    func testZeroMaxItemDoesNotReplaceARealScore() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "ok", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "bad", categoryId: "c", maxPoints: 0, earnedPoints: 5,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 80, accuracy: 0.001)
    }

    func testExtraCreditZeroMaxStaysFinite() throws {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "xc", categoryId: nil, maxPoints: 0, earnedPoints: 5,
                     isExtraCredit: true, weightOverridePct: nil)
            ])
        let result = GradeCalculator.compute(input: input)
        XCTAssertEqual(result.currentPct, 85, accuracy: 0.001)
        XCTAssertNoThrow(try JSONEncoder().encode(result))
    }

    func testDropLowestSkipsNonFiniteRatios() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 1, dropHighestN: 0)],
            items: [
                Item(id: "low", categoryId: "c", maxPoints: 100, earnedPoints: 40,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "high", categoryId: "c", maxPoints: 100, earnedPoints: 90,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "bad", categoryId: "c", maxPoints: 0, earnedPoints: 5,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        // 5/0 is not a score, so it is not ordered. Drop 40, keep 90.
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 90, accuracy: 0.001)
    }

    func testNonFiniteCategoryWeightStaysEncodable() throws {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: .nan, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        let result = GradeCalculator.compute(input: input)
        XCTAssertTrue(result.currentPct.isFinite)
        XCTAssertTrue(result.perCategory.allSatisfy {
            $0.currentPct.isFinite && $0.projectedPct.isFinite && $0.weightPct.isFinite
        })
        XCTAssertNoThrow(try JSONEncoder().encode(result))
    }

    func testNilCategoryAloneUsesItsOwnPercent() {
        // Policy: a regular nil-category item does not enter a weighted category.
        // When it is the only scored work, currentPct is that item's percent (100),
        // not 0, and the letter is not F just because the category is missing.
        // hasGradedWork in AssistantService still counts any earnedPoints != nil,
        // including this row. P4 owns that flag; this test does not change it.
        let input = GradeCalculatorInput(
            categories: [],
            items: [
                Item(id: "i1", categoryId: nil, maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        let result = GradeCalculator.compute(input: input)
        XCTAssertEqual(result.currentPct, 100, accuracy: 0.001)
        XCTAssertNotEqual(result.currentPct, 0)
        XCTAssertEqual(result.currentLetter, "A")
    }

    func testNilCategoryDoesNotChangeWeightedPercent() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "i1", categoryId: "c", maxPoints: 100, earnedPoints: 80,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "loose", categoryId: nil, maxPoints: 100, earnedPoints: 0,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        let result = GradeCalculator.compute(input: input)
        XCTAssertEqual(result.currentPct, 80, accuracy: 0.001)
        XCTAssertEqual(result.projectedPct, 80, accuracy: 0.001)
    }

    func testNilOverridesStayAnEqualMean() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "a", categoryId: "c", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "b", categoryId: "c", maxPoints: 100, earnedPoints: 0,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 50, accuracy: 0.001)
    }

    func testWeightOverrideBlends90And10() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "a", categoryId: "c", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: 90),
                Item(id: "b", categoryId: "c", maxPoints: 100, earnedPoints: 0,
                     isExtraCredit: false, weightOverridePct: 10)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 90, accuracy: 0.001)
    }

    func testNilItemGetsNoWeightWhenOverrideUsesTheWholePool() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "a", categoryId: "c", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: 100),
                Item(id: "b", categoryId: "c", maxPoints: 100, earnedPoints: 0,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 100, accuracy: 0.001)
    }

    func testNegativeOverrideCountsAsZero() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "a", categoryId: "c", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: -20),
                Item(id: "b", categoryId: "c", maxPoints: 100, earnedPoints: 50,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 50, accuracy: 0.001)
    }

    func testNonFiniteOverrideIsSkipped() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 0, dropHighestN: 0)],
            items: [
                Item(id: "bad", categoryId: "c", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: .nan),
                Item(id: "ok", categoryId: "c", maxPoints: 100, earnedPoints: 40,
                     isExtraCredit: false, weightOverridePct: nil)
            ])
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 40, accuracy: 0.001)
    }

    func testDropLowestThenAppliesWeightOverride() {
        let input = GradeCalculatorInput(
            categories: [Cat(id: "c", name: "C", weightPct: 100, dropLowestN: 1, dropHighestN: 0)],
            items: [
                Item(id: "low", categoryId: "c", maxPoints: 100, earnedPoints: 0,
                     isExtraCredit: false, weightOverridePct: 10),
                Item(id: "mid", categoryId: "c", maxPoints: 100, earnedPoints: 60,
                     isExtraCredit: false, weightOverridePct: nil),
                Item(id: "high", categoryId: "c", maxPoints: 100, earnedPoints: 100,
                     isExtraCredit: false, weightOverridePct: 90)
            ])
        // Drop the 0. Kept: 60 at the leftover 10, and 100 at 90 → 96.
        XCTAssertEqual(GradeCalculator.compute(input: input).currentPct, 96, accuracy: 0.001)
    }
}

final class GradeFormatTests: XCTestCase {
    func testWholeAndFractionalNumbers() {
        XCTAssertEqual(GradeFormat.number(30), "30")
        XCTAssertEqual(GradeFormat.number(0), "0")
        XCTAssertEqual(GradeFormat.number(20.5), "20.5")
        XCTAssertEqual(GradeFormat.weightPercent(30), "30%")
        XCTAssertEqual(GradeFormat.weightPercent(20.5), "20.5%")
    }

    func testNonFiniteAndHugeWeightsDoNotTrap() {
        XCTAssertEqual(GradeFormat.number(.nan), "—")
        XCTAssertEqual(GradeFormat.number(.infinity), "—")
        XCTAssertEqual(GradeFormat.weightPercent(.nan), "—")
        XCTAssertEqual(GradeFormat.weightPercent(.infinity), "—")
        let huge = GradeFormat.weightPercent(1e20)
        XCTAssertFalse(huge.isEmpty)
        XCTAssertNotEqual(huge, "—")
        XCTAssertFalse(huge.contains("nan"))
    }
}

final class GradeLoadGateTests: XCTestCase {
    func testStaleCourseGenerationIsDropped() {
        var gate = GradeLoadGate()
        let first = gate.begin("course-a")
        let second = gate.begin("course-b")
        XCTAssertFalse(gate.accepts(generation: first, courseId: "course-a"))
        XCTAssertTrue(gate.accepts(generation: second, courseId: "course-b"))
        XCTAssertFalse(gate.accepts(generation: second, courseId: "course-a"))
        _ = gate.clear()
        XCTAssertFalse(gate.accepts(generation: second, courseId: "course-b"))
    }
}
