import BatteryDomain
import SwiftUI

struct DevicePopoverView: View {
    @ObservedObject var model: BatteryAppModel
    let openSettings: () -> Void
    @State private var selectedDevice: BatteryDevice?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 360, idealWidth: 380, minHeight: 420, idealHeight: 520)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailsView(model: model, device: device)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Host.current().localizedName ?? "This Mac")
                    .font(.headline)
                Text(refreshDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { model.refresh(reason: .manual) }) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(model.isRefreshing ? .degrees(360) : .zero)
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh battery information")
            .accessibilityLabel(model.isRefreshing ? "Refreshing" : "Refresh battery information")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.errorMessage, model.visibleDevices.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                Text("Battery information is unavailable")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleDevices.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(model.isRefreshing ? "Looking for devices…" : "No battery devices found")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleDevices) { device in
                        DeviceRow(
                            device: device,
                            details: { selectedDevice = device },
                            hide: { model.setHidden(true, deviceID: device.id) },
                            pin: { model.setPinned(!device.isPinned, deviceID: device.id) }
                        )
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…", action: openSettings)
                .buttonStyle(.link)
            Spacer()
            Button("Quit", action: { NSApplication.shared.terminate(nil) })
                .buttonStyle(.link)
        }
        .padding(12)
    }

    private var refreshDescription: String {
        if model.isRefreshing { return "Refreshing sources" }
        guard let date = model.lastRefresh else { return "Waiting for first scan" }
        return "Updated \(relativeDate(date))"
    }
}

private struct DeviceRow: View {
    let device: BatteryDevice
    let details: () -> Void
    let hide: () -> Void
    let pin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 20))
                .frame(width: 26)
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName).lineLimit(1)
                HStack(spacing: 5) {
                    Text(stateDescription)
                    if device.freshness != .live {
                        Text("• \(freshnessDescription)")
                    }
                }
                .font(.caption)
                .foregroundColor(device.freshness == .stale ? .orange : .secondary)
            }
            Spacer()
            Text(device.batteryLevel.map { "\($0)%" } ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
            if device.powerState == .charging {
                Image(systemName: "bolt.fill").foregroundColor(.green)
            } else if device.batteryLevel.map({ $0 <= 10 }) == true {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: details)
        .contextMenu {
            Button("Details", action: details)
            Button(device.isPinned ? "Unpin" : "Pin", action: pin)
            Button("Hide", action: hide)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var stateDescription: String {
        switch device.powerState {
        case .unknown: "Battery status"
        case .discharging: "On battery"
        case .charging: "Charging"
        case .charged: "Charged"
        case .paused: "Charging paused"
        case .acPowered: "Power adapter"
        }
    }

    private var freshnessDescription: String {
        switch device.freshness {
        case .live: "Current"
        case .aging: "Updated \(relativeDate(device.observedAt))"
        case .stale: "Stale"
        case .unavailable: "Unavailable"
        case .expired: "Last known"
        }
    }

    private var accessibilityDescription: String {
        let level = device.batteryLevel.map { "\($0) percent" } ?? "battery level unavailable"
        return "\(device.displayName), \(level), \(stateDescription), \(freshnessDescription)"
    }

    private var symbolName: String {
        switch device.category {
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .watch: "applewatch"
        case .earbuds, .caseBattery: "airpodspro"
        case .mouse: "computermouse"
        case .keyboard: "keyboard"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .pencil: "applepencil"
        case .other: "battery.75"
        }
    }
}

private struct DeviceDetailsView: View {
    @ObservedObject var model: BatteryAppModel
    let device: BatteryDevice
    @Environment(\.presentationMode) private var presentationMode
    @State private var lowEnabled: Bool
    @State private var lowThreshold: Int
    @State private var fullEnabled: Bool
    @State private var fullThreshold: Int
    private let hadOverride: Bool

    init(model: BatteryAppModel, device: BatteryDevice) {
        self.model = model
        self.device = device
        let rule = model.alertRule(for: device.id)
        hadOverride = rule != nil
        _lowEnabled = State(initialValue: rule?.lowEnabled ?? model.preferences.lowAlerts)
        _lowThreshold = State(initialValue: rule?.lowThreshold ?? model.preferences.lowThreshold)
        _fullEnabled = State(initialValue: rule?.fullEnabled ?? model.preferences.fullAlerts)
        _fullThreshold = State(initialValue: rule?.fullThreshold ?? model.preferences.fullThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(device.displayName).font(.title2).fontWeight(.semibold)
                    if let modelName = device.model { Text(modelName).foregroundColor(.secondary) }
                }
                Spacer()
                Text(device.batteryLevel.map { "\($0)%" } ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Divider()
            Form {
                Text("State: \(device.powerState.rawValue)")
                Text("Freshness: \(device.freshness.rawValue)")
                Text("Observed: \(relativeDate(device.observedAt))")
                Text("Sources: \(Array(Set(device.sourceKeys.map(\.namespace))).sorted().joined(separator: ", "))")
                Toggle("Low battery alert", isOn: $lowEnabled)
                Stepper("Low threshold: \(lowThreshold)%", value: $lowThreshold, in: 1...50)
                    .disabled(!lowEnabled)
                Toggle("Full battery alert", isOn: $fullEnabled)
                Stepper("Full threshold: \(fullThreshold)%", value: $fullThreshold, in: 50...100)
                    .disabled(!fullEnabled)
            }
            HStack {
                if hadOverride {
                    Button("Use Global Alert Settings") {
                        model.removeAlertOverride(deviceID: device.id)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                Button("Save") {
                    model.saveAlertOverride(
                        deviceID: device.id,
                        lowEnabled: lowEnabled,
                        lowThreshold: lowThreshold,
                        fullEnabled: fullEnabled,
                        fullThreshold: fullThreshold
                    )
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 430)
    }
}

func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}
