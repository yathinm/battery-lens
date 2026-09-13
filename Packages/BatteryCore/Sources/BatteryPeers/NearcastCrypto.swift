import BatteryDomain
import CryptoKit
import Foundation
import Security

public enum NearcastCryptoError: Error, LocalizedError, Sendable {
    case invalidSecret
    case randomGenerationFailed
    case unsupportedProtocol
    case expired
    case invalidLifetime
    case authenticationFailed
    case replay

    public var errorDescription: String? {
        switch self {
        case .invalidSecret: "The trust-group code is invalid."
        case .randomGenerationFailed: "A secure trust-group secret could not be generated."
        case .unsupportedProtocol: "The peer uses an unsupported protocol version."
        case .expired: "The peer message has expired."
        case .invalidLifetime: "The peer message has an invalid lifetime."
        case .authenticationFailed: "The peer message could not be authenticated."
        case .replay: "The peer message was already received."
        }
    }
}

public struct NearcastSecret: Hashable, Sendable {
    public static let byteCount = 32
    public let data: Data

    public init(data: Data) throws {
        guard data.count >= 16 else { throw NearcastCryptoError.invalidSecret }
        self.data = data
    }

    public init(code: String) throws {
        var base64 = code.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { throw NearcastCryptoError.invalidSecret }
        try self.init(data: data)
    }

    public static func generate() throws -> NearcastSecret {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NearcastCryptoError.randomGenerationFailed
        }
        return try NearcastSecret(data: Data(bytes))
    }

    public var code: String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public var groupFingerprint: String {
        SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

public enum NearcastCipher {
    public static func seal<Payload: Encodable>(
        _ payload: Payload,
        secret: NearcastSecret,
        senderID: UUID,
        sequence: UInt64,
        messageType: PeerMessageType,
        createdAt: Date = Date(),
        lifetime: TimeInterval = 120
    ) throws -> PeerEnvelope {
        let messageID = UUID()
        let expiresAt = createdAt.addingTimeInterval(lifetime)
        let key = derivedKey(secret)
        let aad = authenticatedData(
            protocolVersion: PeerEnvelope.currentProtocolVersion,
            messageID: messageID,
            senderID: senderID,
            sequence: sequence,
            createdAt: createdAt,
            expiresAt: expiresAt,
            messageType: messageType
        )
        let plaintext = try JSONEncoder.nearcast.encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        let nonce = sealed.nonce.withUnsafeBytes { Data($0) }
        return PeerEnvelope(
            messageID: messageID,
            senderID: senderID,
            sequence: sequence,
            createdAt: createdAt,
            expiresAt: expiresAt,
            nonce: nonce,
            messageType: messageType,
            ciphertext: sealed.ciphertext,
            authenticationTag: sealed.tag
        )
    }

    public static func open<Payload: Decodable>(
        _ type: Payload.Type,
        envelope: PeerEnvelope,
        secret: NearcastSecret,
        now: Date = Date(),
        maximumLifetime: TimeInterval = 300
    ) throws -> Payload {
        guard envelope.protocolVersion == PeerEnvelope.currentProtocolVersion else {
            throw NearcastCryptoError.unsupportedProtocol
        }
        guard envelope.expiresAt > now else { throw NearcastCryptoError.expired }
        guard envelope.createdAt <= now.addingTimeInterval(30),
              envelope.expiresAt.timeIntervalSince(envelope.createdAt) > 0,
              envelope.expiresAt.timeIntervalSince(envelope.createdAt) <= maximumLifetime
        else { throw NearcastCryptoError.invalidLifetime }

        let aad = authenticatedData(
            protocolVersion: envelope.protocolVersion,
            messageID: envelope.messageID,
            senderID: envelope.senderID,
            sequence: envelope.sequence,
            createdAt: envelope.createdAt,
            expiresAt: envelope.expiresAt,
            messageType: envelope.messageType
        )
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext,
                tag: envelope.authenticationTag
            )
            let plaintext = try AES.GCM.open(box, using: derivedKey(secret), authenticating: aad)
            return try JSONDecoder.nearcast.decode(type, from: plaintext)
        } catch let error as NearcastCryptoError {
            throw error
        } catch {
            throw NearcastCryptoError.authenticationFailed
        }
    }

    private static func derivedKey(_ secret: NearcastSecret) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret.data),
            salt: Data("BatteryLens Nearcast v1".utf8),
            info: Data("snapshot encryption".utf8),
            outputByteCount: 32
        )
    }

    private static func authenticatedData(
        protocolVersion: Int,
        messageID: UUID,
        senderID: UUID,
        sequence: UInt64,
        createdAt: Date,
        expiresAt: Date,
        messageType: PeerMessageType
    ) -> Data {
        let values = [
            String(protocolVersion),
            messageID.uuidString.lowercased(),
            senderID.uuidString.lowercased(),
            String(sequence),
            String(Int64(createdAt.timeIntervalSince1970 * 1_000)),
            String(Int64(expiresAt.timeIntervalSince1970 * 1_000)),
            messageType.rawValue,
        ]
        return Data(values.joined(separator: "|").utf8)
    }
}

public actor ReplayGuard {
    private var lastSequenceBySender: [UUID: UInt64] = [:]
    private var messageIDs: Set<UUID> = []

    public init() {}

    public func accept(_ envelope: PeerEnvelope) throws {
        guard !messageIDs.contains(envelope.messageID),
              envelope.sequence > (lastSequenceBySender[envelope.senderID] ?? 0)
        else { throw NearcastCryptoError.replay }
        messageIDs.insert(envelope.messageID)
        lastSequenceBySender[envelope.senderID] = envelope.sequence
        if messageIDs.count > 2_048 { messageIDs.removeAll(keepingCapacity: true) }
    }

    public func revoke(senderID: UUID) {
        lastSequenceBySender.removeValue(forKey: senderID)
    }
}

private extension JSONEncoder {
    static var nearcast: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var nearcast: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
