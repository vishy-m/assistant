import XCTest
@testable import AssistantBriefings

final class FocusStatusTests: XCTestCase {

    func testReducer() {
        XCTAssertEqual(FocusState.reduce(authorized: false, isFocused: nil), .denied)
        XCTAssertEqual(FocusState.reduce(authorized: false, isFocused: true), .denied)
        XCTAssertEqual(FocusState.reduce(authorized: true, isFocused: nil), .unknown)
        XCTAssertEqual(FocusState.reduce(authorized: true, isFocused: true), .focused)
        XCTAssertEqual(FocusState.reduce(authorized: true, isFocused: false), .notFocused)
    }

    func testUnknownAndFocusedQueue_DeniedAndNotFocusedDeliver() {
        XCTAssertTrue(FocusState.unknown.suppressesDelivery)
        XCTAssertTrue(FocusState.focused.suppressesDelivery)
        XCTAssertFalse(FocusState.denied.suppressesDelivery)
        XCTAssertFalse(FocusState.notFocused.suppressesDelivery)
    }

    func testStoreStartsUnknownAndReportsTransitionToDeliverable() {
        let store = FocusStatusStore()
        XCTAssertEqual(store.state, .unknown)
        XCTAssertTrue(store.update(authorized: true, isFocused: false),
                      "unknown → notFocused opens delivery")
        XCTAssertFalse(store.update(authorized: true, isFocused: false), "no change")
        XCTAssertFalse(store.update(authorized: true, isFocused: true), "now suppressing")
        XCTAssertEqual(store.state, .focused)
        XCTAssertTrue(store.update(authorized: false, isFocused: nil),
                      "focused → denied opens delivery")
    }
}
