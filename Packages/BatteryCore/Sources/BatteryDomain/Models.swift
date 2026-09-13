import Foundation

public struct SourceKey: Codable, Hashable, Sendable, CustomStringConvertible {
    public let namespace: String
    public let identifier: String

    public init(namespace: String, identifier: String) {
        self.namespace = namespace
        self.identifier = identifier
    }

    public var description: String { "\(namespace):\(identifier)" }
}

public enum DeviceCategory: String, Codable, CaseIterable, Sendable {
    case mac, phone, tablet, watch, earbuds, caseBattery = "case"
    case mouse, keyboard, trackpad, pencil, other
}

public enum PowerState: String, Codable, CaseIterable, Sendable {
    case unknown, discharging, charging, charged, paused, acPowered
}

public enum Freshness: String, Codable, CaseIterable, Sendable {
    case live, aging, stale, unavailable, expired
}

public struct DeviceCapabilities: Codable, Hashable, Sendable {
    public var canRefresh: Bool
    public var canDisconnect: Bool
    public var reportsCharging: Bool
    public var reportsLowPowerMode: Bool

    public init(
        canRefresh: Bool = true,
        canDisconnect: Bool = false,
        reportsCharging: Bool = false,
        reportsLowPowerMode: Bool = false
    ) {
        self.canRefresh = canRefresh
        self.canDisconnect = canDisconnect
        self.reportsCharging = reportsCharging
        self.reportsLowPowerMode = reportsLowPowerMode
    }
}

public struct BatteryDevice: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var sourceKeys: Set<SourceKey>
    public var displayName: String
    public var category: DeviceCategory
    public var model: String?
    public var batteryLevel: Int?
    public var powerState: PowerState
    public var lowPowerMode: Bool?
    public var parentID: UUID?
    public var originMacID: UUID
    public var observedAt: Date
    public var receivedAt: Date
    public var freshness: Freshness
    public var isHidden: Bool
    public var isPinned: Bool
    public var capabilities: DeviceCapabilities
    public var preferredSource: SourceKey

    public init(
        id: UUID = UUID(),
        sourceKeys: Set<SourceKey>,
        displayName: String,
        category: DeviceCategory,
        model: String? = nil,
        batteryLevel: Int? = nil,
        powerState: PowerState = .unknown,
        lowPowerMode: Bool? = nil,
        parentID: UUID? = nil,
        originMacID: UUID,
        observedAt: Date,
        receivedAt: Date,
        freshness: Freshness = .live,
        isHidden: Bool = false,
        isPinned: Bool = false,
        capabilities: DeviceCapabilities = .init(),
        preferredSource: SourceKey
    ) {
        self.id = id
        self.sourceKeys = sourceKeys
        self.displayName = displayName
        self.category = category
        self.model = model
        self.batteryLevel = batteryLevel.map { min(100, max(0, $0)) }
        self.powerState = powerState
        self.lowPowerMode = lowPowerMode
        self.parentID = parentID
        self.originMacID = originMacID
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.freshness = freshness
        self.isHidden = isHidden
        self.isPinned = isPinned
        self.capabilities = capabilities
        self.preferredSource = preferredSource
    }
}

public struct ObservationValues: Codable, Hashable, Sendable {
    public var batteryLevel: Int?
    public var powerState: PowerState?
    public var lowPowerMode: Bool?

    public init(batteryLevel: Int? = nil, powerState: PowerState? = nil, lowPowerMode: Bool? = nil) {
        self.batteryLevel = batteryLevel.map { min(100, max(0, $0)) }
        self.powerState = powerState
        self.lowPowerMode = lowPowerMode
    }
}

public struct DeviceObservation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let candidateKey: SourceKey
    public let aliases: Set<SourceKey>
    public let adapterID: String
    public let displayName: String
    public let category: DeviceCategory
    public let model: String?
    public let parentCandidateKey: SourceKey?
    public let values: ObservationValues
    public let quality: Int
    public let observedAt: Date
    public let expiresAt: Date
    public let capabilities: DeviceCapabilities
    public let rawDigest: String?

    public init(
        id: UUID = UUID(),
        candidateKey: SourceKey,
        aliases: Set<SourceKey> = [],
        adapterID: String,
        displayName: String,
        category: DeviceCategory,
        model: String? = nil,
        parentCandidateKey: SourceKey? = nil,
        values: ObservationValues,
        quality: Int,
        observedAt: Date,
        expiresAt: Date,
        capabilities: DeviceCapabilities = .init(),
        rawDigest: String? = nil
    ) {
        self.id = id
        self.candidateKey = candidateKey
        self.aliases = aliases
        self.adapterID = adapterID
        self.displayName = displayName
        self.category = category
        self.model = model
        self.parentCandidateKey = parentCandidateKey
        self.values = values
        self.quality = min(100, max(0, quality))
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.capabilities = capabilities
        self.rawDigest = rawDigest
    }
}
