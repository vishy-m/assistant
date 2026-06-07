import Foundation
import SwiftUI
import AssistantShared

@MainActor
final class ClassStore: ObservableObject {
    @Published var classes: [ClassSummary] = []
    @Published var detail: ClassDetail?
    @Published var eventTypes: [EventTypeDTO] = []

    func refresh() {
        XPCClient.shared.listClasses { [weak self] classes in
            self?.classes = classes
        }
        XPCClient.shared.listEventTypes { [weak self] types in
            self?.eventTypes = types
        }
    }

    func loadDetail(courseId: String) {
        detail = nil
        XPCClient.shared.getClassDetail(courseId: courseId) { [weak self] detail in
            self?.detail = detail
        }
    }
}
