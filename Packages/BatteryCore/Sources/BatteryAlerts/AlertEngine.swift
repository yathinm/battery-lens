import BatteryDomain
import Foundation

public enum AlertKind: String, Codable, Sendable {
    case low, full
}

public struct BatteryAlert: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let kind: AlertKind
    public let deviceID: UUID
    public let deviceName: String
    public let level: Int
    public let occurredAt: Date

    public init(kind: AlertKind, device: BatteryDevice, occurredAt: Date) {
        id = UUID()
        self.kind = kind
        deviceID = device.id
        deviceName = device.displayName
        level = device.batteryLevel ?? 0
        self.occurredAt = occurredAt
    }
}

public actor AlertEngine {
    private var states: [StateKey: AlertState]
    private let suppressionInterval: TimeInterval

    public init(states: [AlertState] = [], suppressionInterval: TimeInterval = 3_600) {
        self.states = Dictionary(uniqueKeysWithValues: states.map { (StateKey($0), $0) })
        self.suppressionInterval = suppressionInterval
    }

    public func evaluate(devices: [BatteryDevice], rules: [AlertRule], now: Date) -> [BatteryAlert] {
        var alerts: [BatteryAlert] = []
        for device in devices where device.freshness == .live || device.freshness == .aging {
            guard let level = device.batteryLevel else { continue }
            let rule = rules.first(where: { $0.deviceID == device.id }) ?? rules.first(where: { $0.deviceID == nil })
            guard let rule else { continue }

            let key = StateKey(deviceID: device.id, ruleID: rule.id)
            var state = states[key] ?? AlertState(deviceID: device.id, ruleID: rule.id)
            guard state.lastObservedAt.map({ device.observedAt > $0 }) ?? true else { continue }

            let zone = Self.zone(level: level, rule: rule)
            let isSnoozed = state.snoozedUntil.map { $0 > now } ?? false
            let isSuppressed = state.lastTriggeredAt.map { now.timeIntervalSince($0) < suppressionInterval } ?? false

            if !isSnoozed && !isSuppressed {
                if rule.lowEnabled,
                   zone == .belowLow,
                   state.previousZone != .belowLow {
                    alerts.append(BatteryAlert(kind: .low, device: device, occurredAt: now))
                    state.lastTriggeredAt = now
                } else if rule.fullEnabled,
                          zone == .atFull,
                          state.previousZone != .atFull,
                          device.powerState == .charging || device.powerState == .charged {
                    alerts.append(BatteryAlert(kind: .full, device: device, occurredAt: now))
                    state.lastTriggeredAt = now
                }
            }

            state.previousZone = zone
            state.lastObservedAt = device.observedAt
            states[key] = state
        }
        return alerts
    }

    public func snooze(deviceID: UUID, until: Date) {
        for key in states.keys where key.deviceID == deviceID {
            states[key]?.snoozedUntil = until
        }
    }

    public func allStates() -> [AlertState] {
        states.values.sorted { lhs, rhs in
            if lhs.deviceID != rhs.deviceID { return lhs.deviceID.uuidString < rhs.deviceID.uuidString }
            return lhs.ruleID.uuidString < rhs.ruleID.uuidString
        }
    }

    private static func zone(level: Int, rule: AlertRule) -> AlertZone {
        if let low = rule.lowThreshold, level <= low { return .belowLow }
        if let full = rule.fullThreshold, level >= full { return .atFull }
        return .normal
    }
}

private struct StateKey: Hashable, Sendable {
    let deviceID: UUID
    let ruleID: UUID

    init(deviceID: UUID, ruleID: UUID) {
        self.deviceID = deviceID
        self.ruleID = ruleID
    }

    init(_ state: AlertState) {
        deviceID = state.deviceID
        ruleID = state.ruleID
    }
}
