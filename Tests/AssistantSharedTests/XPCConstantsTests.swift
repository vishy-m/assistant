import XCTest
@testable import AssistantShared

final class XPCConstantsTests: XCTestCase {
    func testMachServiceNameIsStable() {
        // This name is referenced in the LaunchAgent plist; do not change without
        // also updating Resources/LaunchAgents/com.vishruth.assistant.core.plist.
        XCTAssertEqual(XPCConstants.machServiceName, "com.vishruth.assistant.core")
    }
}
