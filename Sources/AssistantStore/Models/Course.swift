import Foundation
import GRDB

public struct Course: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "course"

    public var id: String
    public var name: String
    public var term: String?
    public var color: String?
    public var targetGrade: String?
    public var gradingScaleJson: String?
    public var syllabusSourcePath: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, name: String, term: String?, color: String?,
                targetGrade: String?, gradingScaleJson: String?, syllabusSourcePath: String?,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.term = term
        self.color = color
        self.targetGrade = targetGrade
        self.gradingScaleJson = gradingScaleJson
        self.syllabusSourcePath = syllabusSourcePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, term, color
        case targetGrade = "target_grade"
        case gradingScaleJson = "grading_scale_json"
        case syllabusSourcePath = "syllabus_source_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
