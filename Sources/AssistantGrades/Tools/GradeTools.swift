import Foundation
import AssistantStore
import AssistantLLM

public enum GradeTools {

    public static func register(into registry: inout ToolRegistry, db: AssistantDB) {
        let gradeRepo = GradeRepository(db: db)

        registry.register(
            tool: LLMTool(
                name: "enter_grade",
                description: "Set the earned points for an existing grade item.",
                inputSchema: #"""
                {
                  "type": "object",
                  "properties": {
                    "item_id": { "type": "string" },
                    "earned_points": { "type": "number" }
                  },
                  "required": ["item_id","earned_points"]
                }
                """#),
            handler: { argsJSON in
                struct Args: Decodable { let item_id: String; let earned_points: Double }
                let args = try JSONDecoder().decode(Args.self,
                                                    from: argsJSON.data(using: .utf8) ?? Data())
                try gradeRepo.setEarnedPoints(itemId: args.item_id, earned: args.earned_points)
                return #"{"status":"updated"}"#
            })

        registry.register(
            tool: LLMTool(
                name: "compute_grade",
                description: "Compute current and projected grade for a course.",
                inputSchema: #"""
                {
                  "type": "object",
                  "properties": {
                    "course_id": { "type": "string" },
                    "projection": { "type": "object" }
                  },
                  "required": ["course_id"]
                }
                """#),
            handler: { argsJSON in
                struct Args: Decodable {
                    let course_id: String
                    let projection: [String: Double]?
                }
                let args = try JSONDecoder().decode(Args.self,
                                                    from: argsJSON.data(using: .utf8) ?? Data())
                let cats = try gradeRepo.categories(forCourse: args.course_id).map {
                    GradeCalculatorInput.CategoryIn(
                        id: $0.id, name: $0.name, weightPct: $0.weightPct,
                        dropLowestN: $0.dropLowestN, dropHighestN: $0.dropHighestN)
                }
                let items = try gradeRepo.items(forCourse: args.course_id).map {
                    GradeCalculatorInput.ItemIn(
                        id: $0.id, categoryId: $0.categoryId,
                        maxPoints: $0.maxPoints, earnedPoints: $0.earnedPoints,
                        isExtraCredit: $0.isExtraCredit,
                        weightOverridePct: $0.weightOverridePct)
                }
                let breakdown = GradeCalculator.compute(input: GradeCalculatorInput(
                    categories: cats, items: items, projection: args.projection ?? [:]))
                struct Out: Encodable {
                    let current_pct: Double
                    let current_letter: String
                    let projected_pct: Double
                    let projected_letter: String
                }
                let out = Out(current_pct: round(breakdown.currentPct * 100) / 100,
                              current_letter: breakdown.currentLetter,
                              projected_pct: round(breakdown.projectedPct * 100) / 100,
                              projected_letter: breakdown.projectedLetter)
                let data = try JSONEncoder().encode(out)
                return String(data: data, encoding: .utf8) ?? "{}"
            })
    }
}
