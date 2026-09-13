import BatteryDomain
import BatteryPeers
import Foundation
import Testing

@Test func nearcastRoundTripAuthenticatesPayload() throws {
    let secret = try NearcastSecret(data: Data(repeating: 7, count: 32))
    let now = Date(timeIntervalSince1970: 10_000)
    let snapshot = WidgetSnapshot(generatedAt: now, originMacID: UUID(), devices: [])
    let envelope = try NearcastCipher.seal(
        snapshot,
        secret: secret,
        senderID: snapshot.originMacID,
        sequence: 1,
        messageType: .snapshot,
        createdAt: now
    )
    let opened = try NearcastCipher.open(
        WidgetSnapshot.self,
        envelope: envelope,
        secret: secret,
        now: now.addingTimeInterval(1)
    )

    #expect(opened == snapshot)
}

@Test func nearcastRejectsWrongSecret() throws {
    let first = try NearcastSecret(data: Data(repeating: 1, count: 32))
    let second = try NearcastSecret(data: Data(repeating: 2, count: 32))
    let now = Date(timeIntervalSince1970: 10_000)
    let envelope = try NearcastCipher.seal(
        ["value": 1],
        secret: first,
        senderID: UUID(),
        sequence: 1,
        messageType: .capability,
        createdAt: now
    )

    #expect(throws: NearcastCryptoError.authenticationFailed) {
        try NearcastCipher.open(
            [String: Int].self,
            envelope: envelope,
            secret: second,
            now: now.addingTimeInterval(1)
        )
    }
}

@Test func replayGuardRejectsDuplicateSequence() async throws {
    let secret = try NearcastSecret(data: Data(repeating: 3, count: 32))
    let now = Date(timeIntervalSince1970: 10_000)
    let sender = UUID()
    let envelope = try NearcastCipher.seal(
        ["value": 1],
        secret: secret,
        senderID: sender,
        sequence: 4,
        messageType: .capability,
        createdAt: now
    )
    let guardActor = ReplayGuard()
    try await guardActor.accept(envelope)

    await #expect(throws: NearcastCryptoError.replay) {
        try await guardActor.accept(envelope)
    }
}

@Test func nearcastRejectsExpiredEnvelope() throws {
    let secret = try NearcastSecret(data: Data(repeating: 4, count: 32))
    let createdAt = Date(timeIntervalSince1970: 10_000)
    let envelope = try NearcastCipher.seal(
        ["value": 1],
        secret: secret,
        senderID: UUID(),
        sequence: 1,
        messageType: .capability,
        createdAt: createdAt,
        lifetime: 10
    )

    #expect(throws: NearcastCryptoError.expired) {
        try NearcastCipher.open(
            [String: Int].self,
            envelope: envelope,
            secret: secret,
            now: createdAt.addingTimeInterval(11)
        )
    }
}

@Test func nearcastCodeRoundTripsWithoutPadding() throws {
    let original = try NearcastSecret.generate()
    let decoded = try NearcastSecret(code: original.code)
    #expect(decoded == original)
}
