import SwiftUI
import ServiceManagement

struct GeneralTab: View {

    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Launch behavior") {
                Toggle("Launch Assistant at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        _Concurrency.Task { await DaemonInstaller.shared.setLaunchAtLogin(on) }
                    }
                Text("Also keeps the background daemon registered so briefings keep firing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Background daemon") {
                HStack {
                    Label(DaemonInstaller.shared.isRegistered ? "Running" : "Not registered",
                          systemImage: DaemonInstaller.shared.isRegistered ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(DaemonInstaller.shared.isRegistered ? .green : .orange)
                    Spacer()
                    Button(DaemonInstaller.shared.isRegistered ? "Re-register" : "Register") {
                        _Concurrency.Task { _ = await DaemonInstaller.shared.register() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
