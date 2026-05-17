import SwiftUI

struct WeekCalendarView: View {
    @ObservedObject var store: DashboardStore
    var body: some View { Text("Week calendar").frame(maxWidth: .infinity, maxHeight: .infinity) }
}
