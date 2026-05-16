import SwiftUI
import KeyboardShortcuts

struct Step4Hotkey: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Pick your summon hotkey").font(.title2.bold())
            Text("The default is ⌃Space. Click below to change it.")
                .foregroundStyle(.secondary)
            KeyboardShortcuts.Recorder("Summon overlay", name: .summon)
                .padding(.top, 8)
            KeyboardShortcuts.Recorder("Crop region (inside overlay)", name: .crop)
            Text("Try it now: press the summon shortcut. The overlay should appear over this window.")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 16)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
