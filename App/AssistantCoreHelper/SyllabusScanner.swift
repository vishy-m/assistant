import Foundation
import AssistantShared
import AssistantStore
import AssistantLLM

/// Runs one syllabus scan: file → text → LLM (single forced tool call) →
/// normalized proposals. Every failure is a status value, never a throw.
struct SyllabusScanner {
    let chain: LLMChain

    func scan(file: ClassFile, className: String, fileURL: URL) async -> SyllabusScanResult {
        guard let text = SyllabusTextExtractor.extract(url: fileURL,
                                                       contentType: file.contentType) else {
            return SyllabusScanResult(fileId: file.id, status: .nothingToScan,
                                      events: [], tasks: [])
        }
        guard chain.hasConfiguredProvider else {
            return SyllabusScanResult(fileId: file.id, status: .llmUnavailable,
                                      events: [], tasks: [])
        }

        let today = ISO8601DateFormatter.string(
            from: Date(), timeZone: .current,
            formatOptions: [.withFullDate, .withDashSeparatorInDate])
        let prompt = SyllabusPrompt.build(className: className, todayISO: today,
                                          documentText: text)
        let tool = LLMTool(
            name: SyllabusPrompt.toolName,
            description: "Record every schedule item extracted from the document.",
            inputSchema: SyllabusPrompt.toolSchemaJSON)

        do {
            let response = try await chain.complete(
                messages: [LLMMessage(role: .user, content: [.text(prompt)])], tools: [tool])
            guard let call = response.toolCalls.first(where: {
                $0.name == SyllabusPrompt.toolName
            }) else {
                return SyllabusScanResult(fileId: file.id,
                                          status: .failed("model returned no extraction"),
                                          events: [], tasks: [])
            }
            let raw = try JSONDecoder().decode(RawSyllabusExtraction.self,
                                               from: Data(call.argumentsJSON.utf8))
            let normalized = SyllabusNormalizer.normalize(raw, className: className,
                                                          scanDate: Date(),
                                                          calendar: Calendar.current)
            return SyllabusScanResult(fileId: file.id, status: .ok,
                                      events: normalized.events, tasks: normalized.tasks)
        } catch {
            return SyllabusScanResult(fileId: file.id,
                                      status: .failed("\(error)"), events: [], tasks: [])
        }
    }
}
