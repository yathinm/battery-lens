@preconcurrency import MultipeerConnectivity
import BatteryDomain
import Foundation

public actor NearcastService {
    public typealias SnapshotHandler = @Sendable (WidgetSnapshot, String) -> Void
    public typealias PeersHandler = @Sendable ([TrustedPeer]) -> Void

    private let localID: UUID
    private var secret: NearcastSecret?
    private var transport: PeerTransport?
    private var sequence: UInt64 = 0
    private var blockedSenders: Set<UUID> = []
    private var peersByID: [UUID: TrustedPeer] = [:]
    private let replayGuard = ReplayGuard()
    private var snapshotHandler: SnapshotHandler?
    private var peersHandler: PeersHandler?

    public init(localID: UUID) {
        self.localID = localID
    }

    public func setSnapshotHandler(_ handler: SnapshotHandler?) {
        snapshotHandler = handler
    }

    public func setPeersHandler(_ handler: PeersHandler?) {
        peersHandler = handler
    }

    public func start(secret: NearcastSecret, displayName: String) {
        stop()
        self.secret = secret
        let transport = PeerTransport(displayName: displayName, groupFingerprint: secret.groupFingerprint)
        transport.onData = { [weak self] data, peerName in
            Task { await self?.receive(data: data, peerName: peerName) }
        }
        transport.onConnectedPeerNames = { [weak self] names in
            Task { await self?.updateConnectedPeerNames(names) }
        }
        self.transport = transport
        transport.start()
    }

    public func stop() {
        transport?.stop()
        transport = nil
        secret = nil
        peersByID.removeAll()
        peersHandler?([])
    }

    public func broadcast(_ snapshot: WidgetSnapshot) throws {
        guard let secret, let transport else { return }
        sequence &+= 1
        let envelope = try NearcastCipher.seal(
            snapshot,
            secret: secret,
            senderID: localID,
            sequence: sequence,
            messageType: .snapshot
        )
        transport.send(try Self.encoder.encode(envelope))
    }

    public func revoke(senderID: UUID) async {
        blockedSenders.insert(senderID)
        peersByID.removeValue(forKey: senderID)
        await replayGuard.revoke(senderID: senderID)
        publishPeers()
    }

    public func trustedPeers() -> [TrustedPeer] {
        peersByID.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func receive(data: Data, peerName: String) async {
        guard let secret,
              let envelope = try? Self.decoder.decode(PeerEnvelope.self, from: data),
              !blockedSenders.contains(envelope.senderID),
              envelope.senderID != localID
        else { return }
        do {
            try await replayGuard.accept(envelope)
            switch envelope.messageType {
            case .snapshot:
                let snapshot = try NearcastCipher.open(
                    WidgetSnapshot.self,
                    envelope: envelope,
                    secret: secret
                )
                peersByID[envelope.senderID] = TrustedPeer(
                    id: envelope.senderID,
                    displayName: peerName,
                    lastSeenAt: Date()
                )
                publishPeers()
                snapshotHandler?(snapshot, peerName)
            case .refreshRequest, .alertRelay, .capability, .error:
                break
            }
        } catch {
            return
        }
    }

    private func updateConnectedPeerNames(_ names: [String]) {
        let connected = Set(names)
        peersByID = peersByID.filter { connected.contains($0.value.displayName) }
        publishPeers()
    }

    private func publishPeers() {
        peersHandler?(trustedPeers())
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private final class PeerTransport: NSObject, @unchecked Sendable {
    var onData: (@Sendable (Data, String) -> Void)?
    var onConnectedPeerNames: (@Sendable ([String]) -> Void)?

    private static let serviceType = "batterylens"
    private let queue = DispatchQueue(label: "com.yathinm.BatteryLens.nearcast", qos: .utility)
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let groupFingerprint: String

    init(displayName: String, groupFingerprint: String) {
        self.groupFingerprint = groupFingerprint
        peerID = MCPeerID(displayName: String(displayName.prefix(63)))
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["group": groupFingerprint],
            serviceType: Self.serviceType
        )
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        queue.async {
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
        }
    }

    func stop() {
        queue.async {
            self.advertiser.stopAdvertisingPeer()
            self.browser.stopBrowsingForPeers()
            self.session.disconnect()
        }
    }

    func send(_ data: Data) {
        queue.async {
            let peers = self.session.connectedPeers
            guard !peers.isEmpty else { return }
            try? self.session.send(data, toPeers: peers, with: .reliable)
        }
    }
}

extension PeerTransport: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard info?["group"] == groupFingerprint,
              !session.connectedPeers.contains(peerID)
        else { return }
        browser.invitePeer(peerID, to: session, withContext: Data(groupFingerprint.utf8), timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}

extension PeerTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let matches = context.map { String(decoding: $0, as: UTF8.self) == groupFingerprint } ?? false
        invitationHandler(matches, matches ? session : nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

extension PeerTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onConnectedPeerNames?(session.connectedPeers.map(\.displayName))
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= 1_048_576 else { return }
        onData?(data, peerID.displayName)
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}

    func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }
}
