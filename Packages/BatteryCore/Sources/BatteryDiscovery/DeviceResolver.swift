import BatteryDomain
import Foundation

public struct FreshnessPolicy: Sendable {
    public var agingAfter: TimeInterval
    public var staleAfter: TimeInterval
    public var expireAfter: TimeInterval

    public init(agingAfter: TimeInterval = 90, staleAfter: TimeInterval = 600, expireAfter: TimeInterval = 1_200) {
        precondition(agingAfter <= staleAfter && staleAfter <= expireAfter)
        self.agingAfter = agingAfter
        self.staleAfter = staleAfter
        self.expireAfter = expireAfter
    }

    public func state(observedAt: Date, now: Date) -> Freshness {
        let age = max(0, now.timeIntervalSince(observedAt))
        if age >= expireAfter { return .expired }
        if age >= staleAfter { return .stale }
        if age >= agingAfter { return .aging }
        return .live
    }
}

public actor DeviceResolver {
    private var devicesByID: [UUID: BatteryDevice]
    private let originMacID: UUID
    private let freshnessPolicy: FreshnessPolicy

    public init(
        existingDevices: [BatteryDevice] = [],
        originMacID: UUID,
        freshnessPolicy: FreshnessPolicy = .init()
    ) {
        devicesByID = Dictionary(uniqueKeysWithValues: existingDevices.map { ($0.id, $0) })
        self.originMacID = originMacID
        self.freshnessPolicy = freshnessPolicy
    }

    @discardableResult
    public func reconcile(_ observations: [DeviceObservation], receivedAt: Date = Date()) -> [BatteryDevice] {
        let ordered = observations.sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt < $1.observedAt }
            return $0.quality < $1.quality
        }

        for observation in ordered {
            reconcile(observation, receivedAt: receivedAt)
        }
        applyFreshness(now: receivedAt)
        return visibleState()
    }

    public func allDevices(now: Date = Date()) -> [BatteryDevice] {
        applyFreshness(now: now)
        return visibleState()
    }

    public func setHidden(_ hidden: Bool, deviceID: UUID) {
        guard var device = devicesByID[deviceID] else { return }
        device.isHidden = hidden
        devicesByID[deviceID] = device
    }

    public func setPinned(_ pinned: Bool, deviceID: UUID) {
        guard var device = devicesByID[deviceID] else { return }
        device.isPinned = pinned
        devicesByID[deviceID] = device
    }

    private func reconcile(_ observation: DeviceObservation, receivedAt: Date) {
        let keys = observation.aliases.union([observation.candidateKey])
        let matches = devicesByID.values.filter { !$0.sourceKeys.isDisjoint(with: keys) }

        var device: BatteryDevice
        if let primary = matches.sorted(by: { $0.observedAt < $1.observedAt }).first {
            device = primary
            for duplicate in matches where duplicate.id != primary.id {
                device.sourceKeys.formUnion(duplicate.sourceKeys)
                device.isHidden = device.isHidden || duplicate.isHidden
                device.isPinned = device.isPinned || duplicate.isPinned
                devicesByID.removeValue(forKey: duplicate.id)
            }
        } else {
            device = BatteryDevice(
                sourceKeys: keys,
                displayName: observation.displayName,
                category: observation.category,
                model: observation.model,
                batteryLevel: observation.values.batteryLevel,
                powerState: observation.values.powerState ?? .unknown,
                lowPowerMode: observation.values.lowPowerMode,
                originMacID: originMacID,
                observedAt: observation.observedAt,
                receivedAt: receivedAt,
                capabilities: observation.capabilities,
                preferredSource: observation.candidateKey
            )
        }

        device.sourceKeys.formUnion(keys)
        if observation.observedAt >= device.observedAt {
            device.displayName = observation.displayName
            device.category = observation.category
            device.model = observation.model ?? device.model
            device.batteryLevel = observation.values.batteryLevel
            device.powerState = observation.values.powerState ?? .unknown
            device.lowPowerMode = observation.values.lowPowerMode
            device.observedAt = observation.observedAt
            device.receivedAt = receivedAt
            device.capabilities = observation.capabilities
            device.preferredSource = observation.candidateKey
        }
        devicesByID[device.id] = device

        if let parentKey = observation.parentCandidateKey,
           let parent = devicesByID.values.first(where: { $0.sourceKeys.contains(parentKey) }) {
            device.parentID = parent.id
            devicesByID[device.id] = device
        }
    }

    private func applyFreshness(now: Date) {
        for (id, var device) in devicesByID {
            if device.freshness != .unavailable {
                device.freshness = freshnessPolicy.state(observedAt: device.observedAt, now: now)
            }
            devicesByID[id] = device
        }
    }

    private func visibleState() -> [BatteryDevice] {
        devicesByID.values.sorted {
            if $0.originMacID != $1.originMacID { return $0.originMacID.uuidString < $1.originMacID.uuidString }
            if $0.category != $1.category { return Self.rank($0.category) < Self.rank($1.category) }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func rank(_ category: DeviceCategory) -> Int {
        switch category {
        case .mac: 0
        case .phone: 1
        case .tablet: 2
        case .watch: 3
        case .earbuds: 4
        case .caseBattery: 5
        case .keyboard: 6
        case .mouse: 7
        case .trackpad: 8
        case .pencil: 9
        case .other: 10
        }
    }
}
