import SwiftUI

struct DueSoonView: View {
    @ObservedObject var store: DashboardStore
    var body: some View { Text("Due Soon").frame(maxWidth: .infinity) }
}
