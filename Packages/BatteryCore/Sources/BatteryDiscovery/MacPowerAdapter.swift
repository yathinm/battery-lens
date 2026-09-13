import BatteryDomain
import Foundation
import IOKit.ps

public actor MacPowerAdapter: DiscoveryAdapter {
    public nonisolated let id = "mac-power"
    private var currentHealth = AdapterHealth(adapterID: "mac-power")

    public init() {}

    public func start() {}
    public func stop() {}

    public func scan() throws -> [DeviceObservation] {
        currentHealth.isScanning = true
        defer { currentHealth.isScanning = false }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            currentHealth.availability = .unavailable
            currentHealth.lastErrorCode = "power_sources_unavailable"
            currentHealth.lastErrorDescription = "macOS did not provide power source information."
            throw DiscoveryError.unavailable("macOS did not provide power source information.")
        }

        let now = Date()
        var observations: [DeviceObservation] = []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any],
                (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let level = description[kIOPSCurrentCapacityKey] as? Int
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
            let sourceState = description[kIOPSPowerSourceStateKey] as? String
            let powerState: PowerState
            if isCharged {
                powerState = .charged
            } else if isCharging {
                powerState = .charging
            } else if sourceState == kIOPSACPowerValue {
                powerState = .acPowered
            } else {
                powerState = .discharging
            }

            observations.append(DeviceObservation(
                candidateKey: SourceKey(namespace: id, identifier: "internal-battery"),
                adapterID: id,
                displayName: Host.current().localizedName ?? "This Mac",
                category: .mac,
                model: nil,
                values: ObservationValues(batteryLevel: level, powerState: powerState),
                quality: 100,
                observedAt: now,
                expiresAt: now.addingTimeInterval(180),
                capabilities: DeviceCapabilities(reportsCharging: true, reportsLowPowerMode: true)
            ))
        }

        currentHealth.availability = .available
        currentHealth.lastSuccess = now
        currentHealth.lastErrorCode = nil
        currentHealth.lastErrorDescription = nil
        return observations
    }

    public func health() -> AdapterHealth { currentHealth }
}
