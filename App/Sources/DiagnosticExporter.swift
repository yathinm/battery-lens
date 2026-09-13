import BatteryDomain
import Foundation

struct DiagnosticExport: Codable {
    struct Application: Codable {
        let version: String
        let build: String
        let operatingSystem: String
        let generatedAt: Date
    }

    struct Settings: Codable {
        let refreshInterval: TimeInterval
        let showPercentage: Bool
        let accessoryDiscovery: Bool
        let genericBLEDiscovery: Bool
        let pairedDeviceDiscovery: Bool
        let lowAlertsEnabled: Bool
        let lowThreshold: Int
        let fullAlertsEnabled: Bool
        let fullThreshold: Int
        let localNetworkSharingEnabled: Bool
    }

    struct DeviceSummary: Codable {
        let category: DeviceCategory
        let powerState: PowerState
        let freshness: Freshness
        let hasBatteryLevel: Bool
        let sourceNamespaces: [String]
        let observedAt: Date
    }

    let application: Application
    let settings: Settings
    let scannerHealth: [AdapterHealth]
    let devices: [DeviceSummary]
    let events: [DiagnosticEvent]
}

@MainActor
enum DiagnosticExporter {
    static func write(
        to url: URL,
        preferences: AppPreferences,
        health: [AdapterHealth],
        devices: [BatteryDevice],
        events: [DiagnosticEvent]
    ) throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let export = DiagnosticExport(
            application: .init(
                version: info["CFBundleShortVersionString"] as? String ?? "unknown",
                build: info["CFBundleVersion"] as? String ?? "unknown",
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                generatedAt: Date()
            ),
            settings: .init(
                refreshInterval: preferences.refreshInterval,
                showPercentage: preferences.showPercentage,
                accessoryDiscovery: preferences.bluetoothAccessories,
                genericBLEDiscovery: preferences.genericBLE,
                pairedDeviceDiscovery: preferences.pairedDevices,
                lowAlertsEnabled: preferences.lowAlerts,
                lowThreshold: preferences.lowThreshold,
                fullAlertsEnabled: preferences.fullAlerts,
                fullThreshold: preferences.fullThreshold,
                localNetworkSharingEnabled: preferences.localNetworkSharing
            ),
            scannerHealth: health,
            devices: devices.map {
                .init(
                    category: $0.category,
                    powerState: $0.powerState,
                    freshness: $0.freshness,
                    hasBatteryLevel: $0.batteryLevel != nil,
                    sourceNamespaces: Array(Set($0.sourceKeys.map(\.namespace))).sorted(),
                    observedAt: $0.observedAt
                )
            },
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(export).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
