import SwiftUI
import AssistantShared

struct ClassesDashboardView: View {
    @ObservedObject var store: ClassStore
    var body: some View { Text("Classes").padding() }
}
