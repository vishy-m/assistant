import XCTest
@testable import AssistantShared

final class FilePreviewKindTests: XCTestCase {
    func testPdfUTIMapsToPdf() {
        XCTAssertEqual(FilePreviewKind.from(contentType: "com.adobe.pdf"), .pdf)
    }

    func testImageUTIMapsToQuickLook() {
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.png"), .quickLook)
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.jpeg"), .quickLook)
    }

    func testUnknownOrEmptyMapsToQuickLook() {
        XCTAssertEqual(FilePreviewKind.from(contentType: ""), .quickLook)
        XCTAssertEqual(FilePreviewKind.from(contentType: "not.a.real.uti"), .quickLook)
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.data"), .quickLook)
    }
}
