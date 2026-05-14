import Foundation
import GRDB

public struct GradeCategory: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "grade_category"

    public var id: String
    public var courseId: String
    public var name: String
    public var weightPct: Double
    public var dropLowestN: Int
    public var dropHighestN: Int

    public init(id: String, courseId: String, name: String, weightPct: Double,
                dropLowestN: Int, dropHighestN: Int) {
        self.id = id
        self.courseId = courseId
        self.name = name
        self.weightPct = weightPct
        self.dropLowestN = dropLowestN
        self.dropHighestN = dropHighestN
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case courseId = "course_id"
        case weightPct = "weight_pct"
        case dropLowestN = "drop_lowest_n"
        case dropHighestN = "drop_highest_n"
    }
}
