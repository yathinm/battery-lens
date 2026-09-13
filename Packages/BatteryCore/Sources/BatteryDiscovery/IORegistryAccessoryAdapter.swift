import BatteryDomain
import Foundation
import IOKit

public actor IORegistryAccessoryAdapter: DiscoveryAdapter {
    public nonisolated let id = "io-registry-accessories"
    private var currentHealth = AdapterHealth(adapterID: "io-registry-accessories")

    public init() {}

    public func start() {}
    public func stop() {}

    public func scan() throws -> [DeviceObservation] {
        currentHealth.isScanning = true
        defer { currentHealth.isScanning = false }

        let classes = [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDDriver",
            "IOHIDDevice",
        ]
        var observationsByKey: [SourceKey: DeviceObservation] = [:]
        let now = Date()

        for className in classes {
            var iterator: io_iterator_t = 0
            let status = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(className), &iterator)
            guard status == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard let observation = Self.observation(for: entry, adapterID: id, now: now) else { continue }
                if let existing = observationsByKey[observation.candidateKey], existing.quality >= observation.quality {
                    continue
                }
                observationsByKey[observation.candidateKey] = observation
            }
        }

        currentHealth.lastSuccess = now
        currentHealth.availability = .available
        currentHealth.lastErrorCode = nil
        currentHealth.lastErrorDescription = nil
        return Array(observationsByKey.values)
    }

    public func health() -> AdapterHealth { currentHealth }

    private static func observation(
        for entry: io_registry_entry_t,
        adapterID: String,
        now: Date
    ) -> DeviceObservation? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanagedProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else { return nil }

        guard let level = integer(in: properties, keys: ["BatteryPercent", "BatteryLevel", "Battery"]),
              (0...100).contains(level)
        else { return nil }

        let name = string(in: properties, keys: ["Product", "ProductName", "DeviceName", "Name"])
            ?? registryName(entry)
            ?? "Bluetooth Accessory"
        let identifier = string(
            in: properties,
            keys: ["SerialNumber", "SerialNumberString", "BD_ADDR", "DeviceAddress", "BluetoothAddress"]
        ) ?? registryIdentifier(entry)
        let model = string(in: properties, keys: ["ModelNumber", "ProductID", "Model"])
        let charging = boolean(in: properties, keys: ["BatteryStatusFlags", "IsCharging", "Charging"])
        let category = category(for: name, properties: properties)

        return DeviceObservation(
            candidateKey: SourceKey(namespace: adapterID, identifier: identifier),
            adapterID: adapterID,
            displayName: name,
            category: category,
            model: model,
            values: ObservationValues(
                batteryLevel: level,
                powerState: charging.map { $0 ? .charging : .discharging }
            ),
            quality: 80,
            observedAt: now,
            expiresAt: now.addingTimeInterval(600),
            capabilities: DeviceCapabilities(reportsCharging: charging != nil)
        )
    }

    private static func integer(in properties: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = properties[key] as? Int { return value }
            if let value = properties[key] as? NSNumber { return value.intValue }
            if let value = properties[key] as? String, let number = Int(value) { return number }
        }
        return nil
    }

    private static func boolean(in properties: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = properties[key] as? Bool { return value }
            if let value = properties[key] as? NSNumber { return value.boolValue }
        }
        return nil
    }

    private static func string(in properties: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = properties[key] as? String, !value.isEmpty { return value }
            if let value = properties[key] as? NSNumber { return value.stringValue }
            if let value = properties[key] as? Data {
                return value.map { String(format: "%02X", $0) }.joined(separator: ":")
            }
        }
        return nil
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return nil }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func registryIdentifier(_ entry: io_registry_entry_t) -> String {
        var id: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS {
            return String(id, radix: 16)
        }
        return "registry-\(entry)"
    }

    private static func category(for name: String, properties: [String: Any]) -> DeviceCategory {
        let haystack = "\(name) \(properties["Product"] ?? "")".lowercased()
        if haystack.contains("airpods") || haystack.contains("beats") || haystack.contains("headphone") {
            return .earbuds
        }
        if haystack.contains("mouse") { return .mouse }
        if haystack.contains("keyboard") { return .keyboard }
        if haystack.contains("trackpad") { return .trackpad }
        return .other
    }
}
