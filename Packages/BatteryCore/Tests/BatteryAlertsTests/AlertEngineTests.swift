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
