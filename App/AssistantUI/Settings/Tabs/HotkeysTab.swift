import SwiftUI
import KeyboardShortcuts

struct HotkeysTab: View {
    var body: some View {
        Form {
            Section("Global") {
                KeyboardShortcuts.Recorder("Summon overlay", name: .summon)
                KeyboardShortcuts.Recorder("Resume last conversation", name: .summonResume)
                KeyboardShortcuts.Recorder("Open dashboard", name: .dashboard)
            }
            Section("Inside overlay") {
                KeyboardShortcuts.Recorder("Crop a screen region", name: .crop)
            }
            Text("Changes apply immediately.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
