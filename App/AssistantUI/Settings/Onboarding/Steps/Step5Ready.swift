import SwiftUI

struct Step5Ready: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("You're ready").font(.title.bold())
            Text("Press your summon hotkey to talk to Assistant.\nIt'll fire morning and evening briefings on schedule, and pop up before exams and big deadlines.\n\nTweak anything later from the menu-bar icon → Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
            Button("Show me the overlay") {
                _Concurrency.Task { @MainActor in OverlayController.shared.summon() }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
