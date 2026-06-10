import XCTest
@testable import AssistantShared

final class ClassFilesDTOsTests: XCTestCase {
    func testRoundTrips() throws {
        let folder = ClassFolderDTO(id: "fo1", courseId: "c1", parentFolderId: nil,
                                    name: "Notes", sortOrder: 0)
        let file = ClassFileDTO(id: "fi1", courseId: "c1", folderId: "fo1", name: "a.pdf",
                                storedName: "fi1.pdf", contentType: "com.adobe.pdf", byteSize: 9)
        let pin = ClassPinDTO(id: "p1", courseId: "c1", fileId: "fi1", x: 1, y: 2,
                              width: 80, height: 90, rotation: 0, zOrder: 0)
        XCTAssertEqual(try JSONDecoder().decode(ClassFolderDTO.self,
            from: JSONEncoder().encode(folder)).name, "Notes")
        XCTAssertEqual(try JSONDecoder().decode(ClassFileDTO.self,
            from: JSONEncoder().encode(file)).storedName, "fi1.pdf")
        XCTAssertEqual(try JSONDecoder().decode(ClassPinDTO.self,
            from: JSONEncoder().encode(pin)).width, 80)
    }
}
