import BatteryAlerts
import BatteryDomain
import Foundation
import Testing

private func makeDevice(level: Int, state: PowerState = .discharging, observedAt: Date) -> BatteryDevice {
    let source = SourceKey(namespace: "test", identifier: "device")
    return BatteryDevice(
        sourceKeys: [source],
        displayName: "Test Device",
        category: .other,
        batteryLevel: level,
        powerState: state,
        originMacID: UUID(),
        observedAt: observedAt,
        receivedAt: observedAt,
        preferredSource: source
    )
}

@Test func lowAlertFiresOnlyOnCrossing() async {
    let rule = AlertRule(lowThreshold: 10, lowEnabled: true)
    let engine = AlertEngine(suppressionInterval: 0)
    let firstDate = Date(timeIntervalSince1970: 100)
    let device = makeDevice(level: 9, observedAt: firstDate)

    #expect(await engine.evaluate(devices: [device], rules: [rule], now: firstDate).count == 1)
    var second = device
    second.observedAt = firstDate.addingTimeInterval(10)
    #expect(await engine.evaluate(devices: [second], rules: [rule], now: second.observedAt).isEmpty)
}

@Test func staleReadingNeverAlerts() async {
    let rule = AlertRule(lowThreshold: 10, lowEnabled: true)
    let engine = AlertEngine()
    var device = makeDevice(level: 1, observedAt: Date())
    device.freshness = .stale

    #expect(await engine.evaluate(devices: [device], rules: [rule], now: Date()).isEmpty)
}

@Test func perDeviceRuleOverridesGlobalRule() async {
    let now = Date(timeIntervalSince1970: 500)
    let device = makeDevice(level: 15, observedAt: now)
    let global = AlertRule(lowThreshold: 10, lowEnabled: true)
    let override = AlertRule(deviceID: device.id, lowThreshold: 20, lowEnabled: true)
    let engine = AlertEngine(suppressionInterval: 0)

    let alerts = await engine.evaluate(devices: [device], rules: [global, override], now: now)
    #expect(alerts.count == 1)
    #expect(alerts[0].kind == .low)
}
