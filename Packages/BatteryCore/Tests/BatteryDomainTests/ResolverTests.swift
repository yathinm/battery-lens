import BatteryDiscovery
import BatteryDomain
import Foundation
import Testing

@Test func resolverMergesExplicitAliasesAndPreservesPreferences() async {
    let origin = UUID()
    let resolver = DeviceResolver(originMacID: origin)
    let now = Date(timeIntervalSince1970: 1_000)
    let firstKey = SourceKey(namespace: "one", identifier: "abc")
    let secondKey = SourceKey(namespace: "two", identifier: "xyz")
    let first = DeviceObservation(
        candidateKey: firstKey,
        adapterID: "one",
        displayName: "Headphones",
        category: .earbuds,
        values: ObservationValues(batteryLevel: 50),
        quality: 50,
        observedAt: now,
        expiresAt: now.addingTimeInterval(600)
    )
    let initial = await resolver.reconcile([first], receivedAt: now)
    await resolver.setHidden(true, deviceID: initial[0].id)

    let second = DeviceObservation(
        candidateKey: secondKey,
        aliases: [firstKey],
        adapterID: "two",
        displayName: "Headphones",
        category: .earbuds,
        values: ObservationValues(batteryLevel: 55),
        quality: 80,
        observedAt: now.addingTimeInterval(1),
        expiresAt: now.addingTimeInterval(600)
    )
    let merged = await resolver.reconcile([second], receivedAt: now.addingTimeInterval(1))

    #expect(merged.count == 1)
    #expect(merged[0].sourceKeys == [firstKey, secondKey])
    #expect(merged[0].batteryLevel == 55)
    #expect(merged[0].isHidden)
}

@Test func resolverExpiresOldDevicesWithoutDeletingPreferences() async {
    let resolver = DeviceResolver(originMacID: UUID(), freshnessPolicy: .init(agingAfter: 10, staleAfter: 20, expireAfter: 30))
    let now = Date(timeIntervalSince1970: 1_000)
    let key = SourceKey(namespace: "test", identifier: "abc")
    let observation = DeviceObservation(
        candidateKey: key,
        adapterID: "test",
        displayName: "Keyboard",
        category: .keyboard,
        values: ObservationValues(batteryLevel: 10),
        quality: 100,
        observedAt: now,
        expiresAt: now.addingTimeInterval(30)
    )
    let initial = await resolver.reconcile([observation], receivedAt: now)
    await resolver.setPinned(true, deviceID: initial[0].id)
    let expired = await resolver.allDevices(now: now.addingTimeInterval(31))

    #expect(expired[0].freshness == .expired)
    #expect(expired[0].isPinned)
}
