import SwiftUI

struct Step1Welcome: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Welcome to Assistant").font(.title.bold())
            Text("Press ⌃Space anywhere to bring up the command bar.\nIt knows your calendar, your tasks, your grades, and your deadlines.\n\nThis short setup gets you running in under 2 minutes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
