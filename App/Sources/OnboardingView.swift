import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: BatteryAppModel
    @ObservedObject private var preferences: AppPreferences
    let complete: () -> Void
    @State private var enableAlerts: Bool
    @State private var launchAtLogin = false

    init(model: BatteryAppModel, complete: @escaping () -> Void) {
        self.model = model
        preferences = model.preferences
        self.complete = complete
        _enableAlerts = State(initialValue: model.preferences.lowAlerts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 42))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to BatteryLens").font(.largeTitle).fontWeight(.semibold)
                    Text("Battery status for this Mac and supported devices, in one quiet place.")
                        .foregroundColor(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Local by default", systemImage: "lock.shield")
                    .font(.headline)
                Text("Battery readings and preferences stay on this Mac. Trusted Mac sharing is disabled until you explicitly create or join a group.")
                    .foregroundColor(.secondary)
            }
            Form {
                Toggle("Show BatteryLens in the menu bar", isOn: $preferences.showMenuBar)
                Toggle("Show BatteryLens in the Dock", isOn: $preferences.showDock)
                Toggle("Discover supported Bluetooth accessories", isOn: $preferences.bluetoothAccessories)
                Toggle("Enable low battery alerts", isOn: $enableAlerts)
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
            Text("macOS asks for Bluetooth or notification access only when the corresponding feature needs it. If you decline, Mac battery monitoring continues to work.")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Start Using BatteryLens") {
                    if !preferences.showMenuBar && !preferences.showDock { preferences.showMenuBar = true }
                    preferences.lowAlerts = enableAlerts
                    if enableAlerts { model.requestNotificationPermission() }
                    if launchAtLogin { model.setLaunchAtLogin(true) }
                    complete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 610, height: 500)
    }
}
