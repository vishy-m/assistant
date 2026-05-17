import SwiftUI

struct DashboardChatView: View {
    @ObservedObject var store: DashboardStore
    var body: some View { Text("Chat").frame(maxWidth: .infinity, maxHeight: .infinity) }
}
