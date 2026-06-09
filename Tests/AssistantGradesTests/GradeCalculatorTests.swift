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
}
