import SwiftUI

struct GradesRailView: View {
    @ObservedObject var store: DashboardStore
    var body: some View { Text("Grades").frame(maxWidth: .infinity) }
}
