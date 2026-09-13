import Foundation

public enum PermissionState: String, Codable, Sendable {
    case notDetermined, authorized, denied, restricted, unsupported
}

public enum AdapterAvailability: String, Codable, Sendable {
    case available, unavailable, disabled
}

public struct AdapterHealth: Codable, Hashable, Sendable {
    public let adapterID: String
    public var permission: PermissionState
    public var availability: AdapterAvailability
    public var isScanning: Bool
    public var lastSuccess: Date?
    public var lastErrorCode: String?
    public var lastErrorDescription: String?

    public init(
        adapterID: String,
        permission: PermissionState = .authorized,
        availability: AdapterAvailability = .available,
        isScanning: Bool = false,
        lastSuccess: Date? = nil,
        lastErrorCode: String? = nil,
        lastErrorDescription: String? = nil
    ) {
        self.adapterID = adapterID
        self.permission = permission
        self.availability = availability
        self.isScanning = isScanning
        self.lastSuccess = lastSuccess
        self.lastErrorCode = lastErrorCode
        self.lastErrorDescription = lastErrorDescription
    }
}

public enum DiscoveryError: Error, LocalizedError, Sendable {
    case permissionDenied
    case unavailable(String)
    case timeout
    case cancelled
    case malformedData(String)
    case incompatibleVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Permission was denied."
        case .unavailable(let reason): reason
        case .timeout: "The battery source did not respond in time."
        case .cancelled: "The scan was cancelled."
        case .malformedData(let reason): "The battery source returned invalid data: \(reason)"
        case .incompatibleVersion(let version): "The battery source uses unsupported schema version \(version)."
        }
    }
}

public protocol DiscoveryAdapter: Sendable {
    var id: String { get }
    func start() async
    func scan() async throws -> [DeviceObservation]
    func stop() async
    func health() async -> AdapterHealth
}

public protocol DeviceRepository: Sendable {
    func loadDevices() async throws -> [BatteryDevice]
    func save(devices: [BatteryDevice]) async throws
    func loadAlertStates() async throws -> [AlertState]
    func save(alertStates: [AlertState]) async throws
    func loadAlertRules() async throws -> [AlertRule]
    func save(alertRules: [AlertRule]) async throws
    func loadAdapterHealth() async throws -> [AdapterHealth]
    func save(adapterHealth: [AdapterHealth]) async throws
}

public enum AlertZone: String, Codable, Sendable {
    case unknown, belowLow, normal, atFull
}

public struct AlertRule: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let deviceID: UUID?
    public var lowThreshold: Int?
    public var fullThreshold: Int?
    public var lowEnabled: Bool
    public var fullEnabled: Bool

    public init(
        id: UUID = UUID(),
        deviceID: UUID? = nil,
        lowThreshold: Int? = 10,
        fullThreshold: Int? = 100,
        lowEnabled: Bool = true,
        fullEnabled: Bool = false
    ) {
        self.id = id
        self.deviceID = deviceID
        self.lowThreshold = lowThreshold.map { min(100, max(0, $0)) }
        self.fullThreshold = fullThreshold.map { min(100, max(0, $0)) }
        self.lowEnabled = lowEnabled
        self.fullEnabled = fullEnabled
    }
}

public struct AlertState: Codable, Hashable, Sendable {
    public let deviceID: UUID
    public let ruleID: UUID
    public var previousZone: AlertZone
    public var lastTriggeredAt: Date?
    public var snoozedUntil: Date?
    public var lastObservedAt: Date?

    public init(
        deviceID: UUID,
        ruleID: UUID,
        previousZone: AlertZone = .unknown,
        lastTriggeredAt: Date? = nil,
        snoozedUntil: Date? = nil,
        lastObservedAt: Date? = nil
    ) {
        self.deviceID = deviceID
        self.ruleID = ruleID
        self.previousZone = previousZone
        self.lastTriggeredAt = lastTriggeredAt
        self.snoozedUntil = snoozedUntil
        self.lastObservedAt = lastObservedAt
    }
}

public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let originMacID: UUID
    public let devices: [WidgetDevice]

    public init(generatedAt: Date, originMacID: UUID, devices: [WidgetDevice]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.originMacID = originMacID
        self.devices = devices
    }
}

public struct WidgetDevice: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let category: DeviceCategory
    public let level: Int?
    public let powerState: PowerState
    public let freshness: Freshness
    public let observedAt: Date
    public let originMacID: UUID

    public init(device: BatteryDevice) {
        id = device.id
        name = device.displayName
        category = device.category
        level = device.batteryLevel
        powerState = device.powerState
        freshness = device.freshness
        observedAt = device.observedAt
        originMacID = device.originMacID
    }
}
