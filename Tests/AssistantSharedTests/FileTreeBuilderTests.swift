import XCTest
@testable import AssistantShared

final class FileTreeBuilderTests: XCTestCase {
    func testBuildsNestedTreeAndPromotesOrphans() {
        let folders = [
            ClassFolderDTO(id: "root", courseId: "c1", parentFolderId: nil, name: "Notes", sortOrder: 0),
            ClassFolderDTO(id: "sub", courseId: "c1", parentFolderId: "root", name: "Wk1", sortOrder: 0),
            ClassFolderDTO(id: "ghost", courseId: "c1", parentFolderId: "missing", name: "Orphan", sortOrder: 1)
        ]
        let files = [
            ClassFileDTO(id: "fA", courseId: "c1", folderId: "root", name: "a.pdf",
                         storedName: "fA.pdf", contentType: "com.adobe.pdf", byteSize: 1),
            ClassFileDTO(id: "loose", courseId: "c1", folderId: nil, name: "loose.pdf",
                         storedName: "loose.pdf", contentType: "com.adobe.pdf", byteSize: 1)
        ]
        let tree = FileTreeBuilder.build(folders: folders, files: files)
        XCTAssertEqual(tree.folders.map(\.folder.name).sorted(), ["Notes", "Orphan"])
        XCTAssertEqual(tree.files.map(\.name), ["loose.pdf"])
        let notes = tree.folders.first { $0.folder.id == "root" }!
        XCTAssertEqual(notes.files.map(\.name), ["a.pdf"])
        XCTAssertEqual(notes.folders.map(\.folder.name), ["Wk1"])
    }
}
