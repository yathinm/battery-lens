import Foundation
import Testing
@testable import BatteryDomain

@Test func batteryLevelIsClamped() {
    let source = SourceKey(namespace: "test", identifier: "device")
    let device = BatteryDevice(
        sourceKeys: [source],
        displayName: "Device",
        category: .other,
        batteryLevel: 120,
        originMacID: UUID(),
        observedAt: Date(),
        receivedAt: Date(),
        preferredSource: source
    )

    #expect(device.batteryLevel == 100)
}

@Test func sourceKeyDescriptionIncludesNamespace() {
    #expect(SourceKey(namespace: "ble", identifier: "123").description == "ble:123")
}
