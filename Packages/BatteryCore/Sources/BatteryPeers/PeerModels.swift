import BatteryDomain
import Foundation

public enum PeerMessageType: String, Codable, Sendable {
    case snapshot, refreshRequest, alertRelay, capability, error
}

public struct PeerEnvelope: Codable, Hashable, Sendable {
    public static let currentProtocolVersion = 1

    public let protocolVersion: Int
    public let messageID: UUID
    public let senderID: UUID
    public let sequence: UInt64
    public let createdAt: Date
    public let expiresAt: Date
    public let nonce: Data
    public let messageType: PeerMessageType
    public let ciphertext: Data
    public let authenticationTag: Data

    public init(
        messageID: UUID = UUID(),
        senderID: UUID,
        sequence: UInt64,
        createdAt: Date,
        expiresAt: Date,
        nonce: Data,
        messageType: PeerMessageType,
        ciphertext: Data,
        authenticationTag: Data
    ) {
        protocolVersion = Self.currentProtocolVersion
        self.messageID = messageID
        self.senderID = senderID
        self.sequence = sequence
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.messageType = messageType
        self.ciphertext = ciphertext
        self.authenticationTag = authenticationTag
    }
}
