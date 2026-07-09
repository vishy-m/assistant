import XCTest
@testable import AssistantShared

final class FilePreviewKindTests: XCTestCase {
    func testPdfUTIMapsToPdf() {
        XCTAssertEqual(FilePreviewKind.from(contentType: "com.adobe.pdf"), .pdf)
    }

    func testImageUTIMapsToImage() {
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.png"), .image)
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.jpeg"), .image)
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.heic"), .image)
    }

    func testUnknownOrEmptyMapsToQuickLook() {
        XCTAssertEqual(FilePreviewKind.from(contentType: ""), .quickLook)
        XCTAssertEqual(FilePreviewKind.from(contentType: "not.a.real.uti"), .quickLook)
        XCTAssertEqual(FilePreviewKind.from(contentType: "public.data"), .quickLook)
    }
}
