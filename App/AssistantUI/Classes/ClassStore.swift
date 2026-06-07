import Foundation
import AssistantShared

@MainActor
final class ClassStore: ObservableObject {
    @Published var classes: [ClassSummary] = []
    @Published var detail: ClassDetail?

    func refresh() {
        XPCClient.shared.listClasses { [weak self] classes in
            self?.classes = classes
        }
    }

    func loadDetail(courseId: String) {
        detail = nil
        XPCClient.shared.getClassDetail(courseId: courseId) { [weak self] detail in
            self?.detail = detail
        }
    }
}
