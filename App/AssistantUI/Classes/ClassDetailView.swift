import SwiftUI
import AssistantShared

struct ClassDetailView: View {
    let courseId: String
    @ObservedObject var store: ClassStore
    var body: some View { Text("Detail: \(courseId)").padding() }
}
