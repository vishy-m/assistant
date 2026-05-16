import Foundation

public struct AppSettings: Codable, Equatable {

    public struct LeadTimes: Codable, Equatable {
        public var exam: [Int]                    // minutes
        public var assignmentDue: [Int]
        public var classCategory: [Int]
        public var clubMeeting: [Int]
        public var internshipDeadline: [Int]
        public var generic: [Int]

        public init(exam: [Int], assignmentDue: [Int], classCategory: [Int],
                    clubMeeting: [Int], internshipDeadline: [Int], generic: [Int]) {
            self.exam = exam
            self.assignmentDue = assignmentDue
            self.classCategory = classCategory
            self.clubMeeting = clubMeeting
            self.internshipDeadline = internshipDeadline
            self.generic = generic
        }

        public static let `default` = LeadTimes(
            exam: [1440, 60],
            assignmentDue: [720, 60],
            classCategory: [10],
            clubMeeting: [30],
            internshipDeadline: [4320, 1440, 60],
            generic: [15])
    }

    public var morningBriefingHour: Int
    public var morningBriefingMinute: Int
    public var eveningBriefingHour: Int
    public var eveningBriefingMinute: Int
    public var leadTimes: LeadTimes
    public var preferredClaudeModel: String       // "claude-sonnet-4-6" | "claude-opus-4-7"
    public var preferredOllamaModel: String       // "gemma4:e2b" | "gemma4:e4b"
    public var gcalOAuthClientID: String?

    public init(morningBriefingHour: Int, morningBriefingMinute: Int,
                eveningBriefingHour: Int, eveningBriefingMinute: Int,
                leadTimes: LeadTimes, preferredClaudeModel: String,
                preferredOllamaModel: String, gcalOAuthClientID: String?) {
        self.morningBriefingHour = morningBriefingHour
        self.morningBriefingMinute = morningBriefingMinute
        self.eveningBriefingHour = eveningBriefingHour
        self.eveningBriefingMinute = eveningBriefingMinute
        self.leadTimes = leadTimes
        self.preferredClaudeModel = preferredClaudeModel
        self.preferredOllamaModel = preferredOllamaModel
        self.gcalOAuthClientID = gcalOAuthClientID
    }

    public static let `default` = AppSettings(
        morningBriefingHour: 8,
        morningBriefingMinute: 0,
        eveningBriefingHour: 21,
        eveningBriefingMinute: 0,
        leadTimes: .default,
        preferredClaudeModel: "claude-sonnet-4-6",
        preferredOllamaModel: "gemma4:e2b",
        gcalOAuthClientID: nil)
}
