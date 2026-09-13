import AppKit
import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let showPercentage = "showPercentage"
        static let bluetoothAccessories = "bluetoothAccessories"
        static let pairedDevices = "pairedDevices"
        static let lowAlerts = "lowAlerts"
        static let lowThreshold = "lowThreshold"
        static let fullAlerts = "fullAlerts"
        static let fullThreshold = "fullThreshold"
        static let alertSound = "alertSound"
        static let showDock = "showDock"
        static let diagnosticRetentionDays = "diagnosticRetentionDays"
    }

    private let defaults: UserDefaults

    @Published var refreshInterval: TimeInterval { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    @Published var showPercentage: Bool { didSet { defaults.set(showPercentage, forKey: Key.showPercentage) } }
    @Published var bluetoothAccessories: Bool { didSet { defaults.set(bluetoothAccessories, forKey: Key.bluetoothAccessories) } }
    @Published var pairedDevices: Bool { didSet { defaults.set(pairedDevices, forKey: Key.pairedDevices) } }
    @Published var lowAlerts: Bool { didSet { defaults.set(lowAlerts, forKey: Key.lowAlerts) } }
    @Published var lowThreshold: Int { didSet { defaults.set(lowThreshold, forKey: Key.lowThreshold) } }
    @Published var fullAlerts: Bool { didSet { defaults.set(fullAlerts, forKey: Key.fullAlerts) } }
    @Published var fullThreshold: Int { didSet { defaults.set(fullThreshold, forKey: Key.fullThreshold) } }
    @Published var alertSound: Bool { didSet { defaults.set(alertSound, forKey: Key.alertSound) } }
    @Published var showDock: Bool {
        didSet {
            defaults.set(showDock, forKey: Key.showDock)
            NSApplication.shared.setActivationPolicy(showDock ? .regular : .accessory)
        }
    }
    @Published var diagnosticRetentionDays: Int {
        didSet { defaults.set(diagnosticRetentionDays, forKey: Key.diagnosticRetentionDays) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.refreshInterval: 60.0,
            Key.showPercentage: true,
            Key.bluetoothAccessories: true,
            Key.pairedDevices: true,
            Key.lowAlerts: true,
            Key.lowThreshold: 10,
            Key.fullAlerts: false,
            Key.fullThreshold: 100,
            Key.alertSound: true,
            Key.showDock: false,
            Key.diagnosticRetentionDays: 7,
        ])
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
        showPercentage = defaults.bool(forKey: Key.showPercentage)
        bluetoothAccessories = defaults.bool(forKey: Key.bluetoothAccessories)
        pairedDevices = defaults.bool(forKey: Key.pairedDevices)
        lowAlerts = defaults.bool(forKey: Key.lowAlerts)
        lowThreshold = defaults.integer(forKey: Key.lowThreshold)
        fullAlerts = defaults.bool(forKey: Key.fullAlerts)
        fullThreshold = defaults.integer(forKey: Key.fullThreshold)
        alertSound = defaults.bool(forKey: Key.alertSound)
        showDock = defaults.bool(forKey: Key.showDock)
        diagnosticRetentionDays = defaults.integer(forKey: Key.diagnosticRetentionDays)
    }
}
