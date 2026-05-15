import Foundation
import AssistantLLM
import AssistantStore

public struct BriefingComposer {

    private let chain: LLMChain

    public init(chain: LLMChain) { self.chain = chain }

    public struct MorningContext {
        public let items: [String]
        public init(items: [String]) { self.items = items }
    }

    public func compose(morning ctx: MorningContext) async -> String {
        let systemHint = "You are a brief, friendly assistant writing a morning briefing for a busy college student. Keep it under 5 lines. No fluff."
        let user = "Items for today:\n" + ctx.items.map { "- \($0)" }.joined(separator: "\n")
            + "\n\nWrite a short morning briefing."
        let messages = [
            LLMMessage(role: .system, content: [.text(systemHint)]),
            LLMMessage(role: .user, content: [.text(user)])
        ]
        do {
            let resp = try await chain.complete(messages: messages, tools: [])
            let t = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? BriefingTemplates.morning(items: ctx.items) : t
        } catch {
            return BriefingTemplates.morning(items: ctx.items)
        }
    }

    public struct EveningContext {
        public let remaining: [String]
        public let tomorrow: [String]
        public init(remaining: [String], tomorrow: [String]) {
            self.remaining = remaining
            self.tomorrow = tomorrow
        }
    }

    public func compose(evening ctx: EveningContext) async -> String {
        let systemHint = "You are a brief, friendly assistant writing an end-of-day wrap-up. <5 lines."
        let user = "Remaining today: \(ctx.remaining.joined(separator: "; "))\nTomorrow: \(ctx.tomorrow.joined(separator: "; "))\n\nWrite the wrap-up."
        let messages = [
            LLMMessage(role: .system, content: [.text(systemHint)]),
            LLMMessage(role: .user, content: [.text(user)])
        ]
        do {
            let resp = try await chain.complete(messages: messages, tools: [])
            let t = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? BriefingTemplates.evening(remaining: ctx.remaining, tomorrow: ctx.tomorrow) : t
        } catch {
            return BriefingTemplates.evening(remaining: ctx.remaining, tomorrow: ctx.tomorrow)
        }
    }

    public func composePreEvent(title: String, minutesUntil: Int) async -> String {
        // Short enough that we keep deterministic by default
        BriefingTemplates.preEvent(title: title, minutesUntil: minutesUntil)
    }

    public func composeRisk(finding: RiskFinding) async -> String {
        let systemHint = "Write a single 1-line alert. <120 chars. End with a clarifying question if appropriate."
        let user = "Risk: \(finding.summary)\nWrite the alert."
        let messages = [
            LLMMessage(role: .system, content: [.text(systemHint)]),
            LLMMessage(role: .user, content: [.text(user)])
        ]
        do {
            let resp = try await chain.complete(messages: messages, tools: [])
            let t = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? finding.summary : t
        } catch {
            return finding.summary
        }
    }
}
