import Foundation
import AssistantShared
import AssistantStore
import AssistantGrades

@MainActor
final class GradeStore: ObservableObject {

    @Published var courses: [Course] = []
    @Published var selectedCourseId: String?
    @Published var categories: [GradeCategory] = []
    @Published var items: [GradeItem] = []
    @Published var breakdown: GradeBreakdown?
    @Published var projection: [String: Double] = [:]

    private var loadGate = GradeLoadGate()

    func refreshCourses() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.listCourses { courses in
                self.courses = courses
                cont.resume()
            }
        }
    }

    /// Drops the previous course's rows before any await, and bumps the load
    /// generation so a late reply cannot write them back.
    @discardableResult
    func prepareCourseLoad(_ id: String) -> UInt64 {
        let generation = loadGate.begin(id)
        selectedCourseId = id
        categories = []
        items = []
        breakdown = nil
        return generation
    }

    func clearCourseSelection() {
        _ = loadGate.clear()
        selectedCourseId = nil
        categories = []
        items = []
        breakdown = nil
    }

    func selectCourse(_ id: String) async {
        let generation = prepareCourseLoad(id)
        await finishCourseLoad(id, generation: generation)
    }

    func finishCourseLoad(_ id: String, generation: UInt64) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.listGradeData(courseId: id) { cats, items in
                guard self.loadGate.accepts(generation: generation, courseId: id) else {
                    cont.resume()
                    return
                }
                self.categories = cats
                self.items = items
                cont.resume()
            }
        }
        guard loadGate.accepts(generation: generation, courseId: id) else { return }
        await refreshBreakdown()
    }

    func refreshBreakdown() async {
        guard let id = selectedCourseId else { return }
        let generation = loadGate.generation
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.computeGrade(courseId: id,
                                          projection: projection.isEmpty ? nil : projection) { bd in
                guard self.loadGate.accepts(generation: generation, courseId: id) else {
                    cont.resume()
                    return
                }
                self.breakdown = bd
                cont.resume()
            }
        }
    }

    func deleteCategory(_ id: String) async {
        let deleted: Bool = await withCheckedContinuation { cont in
            XPCClient.shared.deleteCategory(id: id) { ok in
                cont.resume(returning: ok)
            }
        }
        guard deleted, let courseId = selectedCourseId else { return }
        await selectCourse(courseId)
    }

    func deleteItem(_ id: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.deleteItem(id: id) { _ in cont.resume() }
        }
        if let courseId = selectedCourseId { await selectCourse(courseId) }
    }

    func deleteCourse(_ id: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.deleteCourse(id: id) { _ in cont.resume() }
        }
        if selectedCourseId == id {
            clearCourseSelection()
        }
        await refreshCourses()
    }
}
