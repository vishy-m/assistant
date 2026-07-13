import XCTest
import PDFKit
@testable import AssistantStore

final class SyllabusTextExtractorTests: XCTestCase {
    private func tempFile(_ name: String, _ contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url)
        return url
    }

    func testTxtAndMdExtract() throws {
        let txt = try tempFile("syllabus.txt", Data("Office hours Wed 2pm".utf8))
        XCTAssertEqual(SyllabusTextExtractor.extract(url: txt,
                                                     contentType: "public.plain-text"),
                       "Office hours Wed 2pm")
        let md = try tempFile("s.md", Data("# Deadlines\nHW1 due 2026-09-03".utf8))
        XCTAssertEqual(SyllabusTextExtractor.extract(url: md,
                                                     contentType: "net.daringfireball.markdown"),
                       "# Deadlines\nHW1 due 2026-09-03")
    }

    func testPDFExtracts() throws {
        // Build a real one-page PDF with drawn text via PDFKit annotation-free
        // route: NSAttributedString -> data provider.
        let text = "Midterm exam October 8 at 7pm"
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        let attr = NSAttributedString(string: text,
                                      attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        let url = try tempFile("s.pdf", pdfData as Data)
        let extracted = SyllabusTextExtractor.extract(url: url,
                                                      contentType: "com.adobe.pdf")
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted!.contains("Midterm"))
    }

    func testUnsupportedAndEmptyReturnNil() throws {
        let png = try tempFile("x.png", Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertNil(SyllabusTextExtractor.extract(url: png, contentType: "public.png"))
        let empty = try tempFile("e.txt", Data("   \n ".utf8))
        XCTAssertNil(SyllabusTextExtractor.extract(url: empty,
                                                   contentType: "public.plain-text"))
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).txt")
        XCTAssertNil(SyllabusTextExtractor.extract(url: missing,
                                                   contentType: "public.plain-text"))
    }

    func testCapAt60k() throws {
        let big = String(repeating: "a", count: 70_000)
        let url = try tempFile("big.txt", Data(big.utf8))
        let out = SyllabusTextExtractor.extract(url: url,
                                                contentType: "public.plain-text")
        XCTAssertEqual(out?.count, 60_000)
    }
}
