import XCTest
@testable import AssistantShared

final class GoogleConnectGateTests: XCTestCase {

    func testStartsOnlyWhenBothSavesSucceededAndFieldsNonEmpty() {
        XCTAssertTrue(GoogleConnectGate.canStart(settingsSaved: true, secretSaved: true,
                                                 clientID: "cid", secret: "sec"))
        XCTAssertFalse(GoogleConnectGate.canStart(settingsSaved: false, secretSaved: true,
                                                  clientID: "cid", secret: "sec"))
        XCTAssertFalse(GoogleConnectGate.canStart(settingsSaved: true, secretSaved: false,
                                                  clientID: "cid", secret: "sec"))
        XCTAssertFalse(GoogleConnectGate.canStart(settingsSaved: true, secretSaved: true,
                                                  clientID: "", secret: "sec"))
        XCTAssertFalse(GoogleConnectGate.canStart(settingsSaved: true, secretSaved: true,
                                                  clientID: "cid", secret: ""))
        XCTAssertFalse(GoogleConnectGate.canStart(settingsSaved: true, secretSaved: true,
                                                  clientID: "  ", secret: " \n"))
    }

    func testCanAttemptRequiresBothFields() {
        XCTAssertTrue(GoogleConnectGate.canAttempt(clientID: "cid", secret: "sec"))
        XCTAssertFalse(GoogleConnectGate.canAttempt(clientID: "cid", secret: ""))
        XCTAssertFalse(GoogleConnectGate.canAttempt(clientID: "", secret: "sec"))
    }

    func testFailureMessage() {
        XCTAssertNil(GoogleConnectGate.saveFailureMessage(settingsSaved: true, secretSaved: true))
        XCTAssertNotNil(GoogleConnectGate.saveFailureMessage(settingsSaved: false, secretSaved: true))
        XCTAssertNotNil(GoogleConnectGate.saveFailureMessage(settingsSaved: true, secretSaved: false))
    }
}
