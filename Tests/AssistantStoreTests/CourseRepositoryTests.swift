import XCTest
@testable import AssistantStore

final class CourseRepositoryTests: XCTestCase {

    func testInsertAndFetchById() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        let course = Course(id: "c1", name: "Operating Systems", term: "Spring 2026",
                            color: "#FF9933", targetGrade: "A-",
                            gradingScaleJson: nil, syllabusSourcePath: nil)
        try repo.insert(course)

        let got = try repo.find(id: "c1")
        XCTAssertEqual(got?.name, "Operating Systems")
    }

    func testListAll() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        try repo.insert(Course(id: "c1", name: "A", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        try repo.insert(Course(id: "c2", name: "B", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        XCTAssertEqual(try repo.all().count, 2)
    }

    func testDelete() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        try repo.insert(Course(id: "c1", name: "A", term: nil, color: nil,
                               targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        try repo.delete(id: "c1")
        XCTAssertNil(try repo.find(id: "c1"))
    }

    func testDeleteRemovesThatCoursesClassRowsOnly() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        for id in ["c1", "c2"] {
            try repo.insert(Course(id: id, name: id, term: nil, color: nil,
                                   targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil))
        }
        try db.queue.write { db in
            for c in ["c1", "c2"] {
                try ClassFolder(id: "fo-\(c)", courseId: c, parentFolderId: nil, name: "N").insert(db)
                try ClassFile(id: "fi-\(c)", courseId: c, folderId: "fo-\(c)", name: "a",
                              storedName: "fi-\(c).pdf", contentType: "x", byteSize: 1).insert(db)
                try ClassPin(id: "p-\(c)", courseId: c, fileId: "fi-\(c)", x: 0, y: 0,
                             width: 1, height: 1).insert(db)
            }
        }
        let removed = try repo.delete(id: "c1")
        XCTAssertEqual(removed.map(\.storedName), ["fi-c1.pdf"])
        XCTAssertEqual(removed.map(\.courseId), ["c1"])
        XCTAssertNil(try repo.find(id: "c1"))
        XCTAssertTrue(try ClassFolderRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertTrue(try ClassFileRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertTrue(try ClassPinRepository(db: db).all(courseId: "c1").isEmpty)
        XCTAssertEqual(try ClassFileRepository(db: db).all(courseId: "c2").count, 1)
        XCTAssertEqual(try ClassFolderRepository(db: db).all(courseId: "c2").count, 1)
        XCTAssertEqual(try ClassPinRepository(db: db).all(courseId: "c2").count, 1)
    }

    func testCourseRoundTripsContactFields() throws {
        let db = try InMemoryDB.make()
        let repo = CourseRepository(db: db)
        var course = Course(id: "c1", name: "OS", term: "Fall", color: "4F6B7A",
                            targetGrade: nil, gradingScaleJson: nil, syllabusSourcePath: nil)
        course.professorName = "Dr. Ada"
        course.professorEmail = "ada@uni.edu"
        course.classroom = "ENS 207"
        course.iconName = "book.closed"
        try repo.insert(course)

        let loaded = try repo.find(id: "c1")
        XCTAssertEqual(loaded?.professorName, "Dr. Ada")
        XCTAssertEqual(loaded?.professorEmail, "ada@uni.edu")
        XCTAssertEqual(loaded?.classroom, "ENS 207")
        XCTAssertEqual(loaded?.iconName, "book.closed")
    }
}
