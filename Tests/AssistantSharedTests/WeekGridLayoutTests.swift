import XCTest
@testable import AssistantShared

final class WeekGridLayoutTests: XCTestCase {

    private let layout = WeekGridLayout(hourHeight: 60, dayStartHour: 0)

    func testTimeToOffset() {
        let base = Date(timeIntervalSince1970: 0)
        let twoThirty = base.addingTimeInterval(2.5 * 3600)
        XCTAssertEqual(layout.yOffset(for: twoThirty, dayStart: base), 150, accuracy: 0.001)
    }

    func testOffsetToSnappedTime() {
        let base = Date(timeIntervalSince1970: 0)
        let snapped = layout.time(forYOffset: 70, dayStart: base)
        XCTAssertEqual(snapped.timeIntervalSince(base), 75 * 60, accuracy: 0.001)
    }

    func testEventBlockHeight() {
        XCTAssertEqual(layout.height(forDurationSeconds: 3600), 60, accuracy: 0.001)
        XCTAssertEqual(layout.height(forDurationSeconds: 900), 15, accuracy: 0.001)
    }

    func testNonOverlappingEventsEachGetFullWidth() {
        let base = Date(timeIntervalSince1970: 0)
        let cols = WeekGridLayout.columns(for: [
            .init(id: "a", start: base, end: base.addingTimeInterval(3600)),
            .init(id: "b", start: base.addingTimeInterval(7200),
                           end: base.addingTimeInterval(10800))
        ])
        XCTAssertEqual(cols["a"]?.columnCount, 1)
        XCTAssertEqual(cols["b"]?.columnCount, 1)
    }

    func testOverlappingEventsSplitIntoColumns() {
        let base = Date(timeIntervalSince1970: 0)
        let cols = WeekGridLayout.columns(for: [
            .init(id: "a", start: base, end: base.addingTimeInterval(3600)),
            .init(id: "b", start: base.addingTimeInterval(1800),
                           end: base.addingTimeInterval(5400))
        ])
        XCTAssertEqual(cols["a"]?.columnCount, 2)
        XCTAssertEqual(cols["b"]?.columnCount, 2)
        XCTAssertNotEqual(cols["a"]?.columnIndex, cols["b"]?.columnIndex)
    }
}
