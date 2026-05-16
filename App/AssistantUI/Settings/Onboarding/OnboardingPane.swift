import SwiftUI

struct OnboardingPane: View {
    @ObservedObject var store: SettingsStore
    let onFinish: () -> Void

    @State private var step: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            Group {
                switch step {
                case 0: Step1Welcome()
                case 1: Step2APIKeys(store: store)
                case 2: Step3GoogleCalendar(store: store)
                case 3: Step4Hotkey()
                default: Step5Ready()
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .task { await store.reload() }
    }

    private var stepHeader: some View {
        HStack {
            ForEach(0..<5) { i in
                Circle()
                    .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            Spacer()
            Text("Step \(step + 1) of 5").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Back") { step -= 1 } }
            Spacer()
            if step < 4 {
                Button("Continue") { step += 1 }.keyboardShortcut(.return)
            } else {
                Button("Finish") { onFinish() }.keyboardShortcut(.return)
            }
        }
        .padding(20)
    }
}
