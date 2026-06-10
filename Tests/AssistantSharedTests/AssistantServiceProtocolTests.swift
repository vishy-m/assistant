import XCTest
import Foundation
@testable import AssistantShared

final class AssistantServiceProtocolTests: XCTestCase {

    func testProtocolCanBeUsedAsXPCInterface() {
        // NSXPCInterface(with:) crashes at runtime if the protocol isn't @objc
        // or if its methods aren't bridgeable. Constructing it is the assertion.
        let iface = NSXPCInterface(with: AssistantServiceProtocol.self)
        XCTAssertNotNil(iface)
    }

    func testProtocolDeclaresPingMethod() {
        // Reflection-based check: protocol must declare a `ping(reply:)` selector.
        let selector = #selector(AssistantServiceProtocol.ping(reply:))
        XCTAssertEqual(selector.description, "pingWithReply:")
    }
}
