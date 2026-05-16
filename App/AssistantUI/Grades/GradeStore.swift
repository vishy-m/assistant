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

    func refreshCourses() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.listCourses { courses in
                self.courses = courses
                cont.resume()
            }
        }
    }

    func selectCourse(_ id: String) async {
        selectedCourseId = id
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.listGradeData(courseId: id) { cats, items in
                self.categories = cats
                self.items = items
                cont.resume()
            }
        }
        await refreshBreakdown()
    }

    func refreshBreakdown() async {
        guard let id = selectedCourseId else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            XPCClient.shared.computeGrade(courseId: id,
                                          projection: projection.isEmpty ? nil : projection) { bd in
                self.breakdown = bd
                cont.resume()
            }
        }
    }
}
