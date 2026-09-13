import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BatteryAppModel
    @ObservedObject private var preferences: AppPreferences
    @State private var showEraseConfirmation = false

    init(model: BatteryAppModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gear") }
            discovery
                .tabItem { Label("Discovery", systemImage: "antenna.radiowaves.left.and.right") }
            alerts
                .tabItem { Label("Alerts", systemImage: "bell") }
            diagnostics
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
    }

    private var general: some View {
        Form {
            Toggle("Show percentage in the menu bar", isOn: $preferences.showPercentage)
            Toggle("Show BatteryLens in the Dock", isOn: $preferences.showDock)
            Picker("Refresh interval", selection: $preferences.refreshInterval) {
                Text("30 seconds").tag(30.0)
                Text("1 minute").tag(60.0)
                Text("5 minutes").tag(300.0)
                Text("10 minutes").tag(600.0)
            }
            if !model.hiddenDevices.isEmpty {
                Section(header: Text("Hidden Devices")) {
                    ForEach(model.hiddenDevices) { device in
                        HStack {
                            Text(device.displayName)
                            Spacer()
                            Button("Restore") { model.setHidden(false, deviceID: device.id) }
                        }
                    }
                }
            }
        }
    }

    private var discovery: some View {
        Form {
            Toggle("Apple and Bluetooth accessories", isOn: $preferences.bluetoothAccessories)
            Toggle("Paired iPhone and iPad", isOn: $preferences.pairedDevices)
            Text("Source changes apply after BatteryLens is relaunched.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var alerts: some View {
        Form {
            Toggle("Low battery alerts", isOn: $preferences.lowAlerts)
            Stepper("Low threshold: \(preferences.lowThreshold)%", value: $preferences.lowThreshold, in: 1...50)
                .disabled(!preferences.lowAlerts)
            Toggle("Full battery alerts", isOn: $preferences.fullAlerts)
            Stepper("Full threshold: \(preferences.fullThreshold)%", value: $preferences.fullThreshold, in: 50...100)
                .disabled(!preferences.fullAlerts)
            Toggle("Play alert sound", isOn: $preferences.alertSound)
            Button("Enable Notifications") { model.requestNotificationPermission() }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.adapterHealth.isEmpty {
                Text("Scanner status will appear after the first refresh.").foregroundColor(.secondary)
            } else {
                List(model.adapterHealth, id: \.adapterID) { health in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(health.adapterID)
                            Text(health.lastErrorDescription ?? health.availability.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(health.lastErrorDescription == nil ? .secondary : .orange)
                        }
                        Spacer()
                        if health.isScanning { ProgressView().controlSize(.small) }
                        Text(health.permission.rawValue.capitalized).font(.caption)
                    }
                }
            }
            HStack {
                Button("Refresh All Sources") { model.refresh(reason: .manual) }
                Spacer()
                Button("Erase Local Device Data") { showEraseConfirmation = true }
            }
        }
        .alert(isPresented: $showEraseConfirmation) {
            Alert(
                title: Text("Erase local device data?"),
                message: Text("Battery readings, aliases, scanner state, and alert state will be removed. Your display preferences remain."),
                primaryButton: .destructive(Text("Erase")) { model.eraseDevices() },
                secondaryButton: .cancel()
            )
        }
    }

    private var privacy: some View {
        Form {
            Text("BatteryLens stores battery readings and preferences on this Mac. It does not require an account or an external service.")
            Picker("Diagnostic retention", selection: $preferences.diagnosticRetentionDays) {
                Text("1 day").tag(1)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
            }
            Text("Local network sharing is off unless you enable it in a future sharing setup.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
