import XCTest
@testable import AssistantShared

final class EventClientSlotTests: XCTestCase {
    private final class Box {}

    func testClearIfSameOnlyClearsTheMatchingObject() {
        let slot = EventClientSlot<Box>()
        let a = Box(), b = Box()
        XCTAssertNil(slot.replace(a))
        XCTAssertTrue(slot.replace(b) === a)        // previous handed back for invalidation
        slot.clearIfSame(a)                          // stale invalidation handler
        XCTAssertTrue(slot.current === b)
        slot.clearIfSame(b)
        XCTAssertNil(slot.current)
    }

    func testWithCurrentHandsBackTheStoredObject() {
        let slot = EventClientSlot<Box>()
        XCTAssertNil(slot.withCurrent { $0 })
        let a = Box()
        slot.replace(a)
        XCTAssertTrue(slot.withCurrent { $0 } === a)
    }

    func testConcurrentReplaceAndStaleClearNeverDropsLatest() {
        let slot = EventClientSlot<Box>()
        let iterations = 4000
        var latest: [Box] = (0..<iterations).map { _ in Box() }
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let mine = latest[i]
            let previous = slot.replace(mine)
            if let previous { slot.clearIfSame(previous) }   // old connection invalidates
        }
        // Whatever won last must still be stored: only stale objects were cleared.
        let current = slot.current
        XCTAssertNotNil(current)
        latest.removeAll()
    }
}
