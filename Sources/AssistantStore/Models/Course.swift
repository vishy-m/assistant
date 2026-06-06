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
    public var creditHours: Double?
    public var professorName: String?
    public var professorEmail: String?
    public var classroom: String?
    public var iconName: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String, name: String, term: String?, color: String?,
                targetGrade: String?, gradingScaleJson: String?, syllabusSourcePath: String?,
                creditHours: Double? = nil,
                professorName: String? = nil, professorEmail: String? = nil,
                classroom: String? = nil, iconName: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.term = term
        self.color = color
        self.targetGrade = targetGrade
        self.gradingScaleJson = gradingScaleJson
        self.syllabusSourcePath = syllabusSourcePath
        self.creditHours = creditHours
        self.professorName = professorName
        self.professorEmail = professorEmail
        self.classroom = classroom
        self.iconName = iconName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, term, color
        case targetGrade = "target_grade"
        case gradingScaleJson = "grading_scale_json"
        case syllabusSourcePath = "syllabus_source_path"
        case creditHours = "credit_hours"
        case professorName = "professor_name"
        case professorEmail = "professor_email"
        case classroom
        case iconName = "icon_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
