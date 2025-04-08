import Foundation
import MultipeerConnectivity
import NearbyInteraction
import UIKit

struct MPCSessionConstants {
    static let kKeyIdentity: String = "identity"
}

class MPCSession: NSObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    var peerDataHandler: ((Data, MCPeerID) -> Void)?
    var peerConnectedHandler: ((MCPeerID) -> Void)?
    var peerDisconnectedHandler: ((MCPeerID) -> Void)?

    private let serviceString: String
    private let identityString: String
    private let maxNumPeers: Int
    private let localPeerID = MCPeerID(displayName: UIDevice.current.name)
    private let mcSession: MCSession
    private let mcAdvertiser: MCNearbyServiceAdvertiser
    private var mcBrowser: MCNearbyServiceBrowser?

    init(service: String, identity: String, maxPeers: Int) {
        self.serviceString = service
        self.identityString = identity
        self.maxNumPeers = maxPeers

        self.mcSession = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.mcAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: [MPCSessionConstants.kKeyIdentity: identityString], serviceType: serviceString)
        self.mcBrowser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceString)

        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcBrowser?.delegate = self
    }

    func start() {
        mcAdvertiser.startAdvertisingPeer()
        if mcBrowser == nil {
            mcBrowser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceString)
            mcBrowser?.delegate = self
        }
        mcBrowser?.startBrowsingForPeers()
    }

    func suspend() {
        mcAdvertiser.stopAdvertisingPeer()
        mcBrowser = nil
    }

    func invalidate() {
        suspend()
        mcSession.disconnect()
    }

    func sendDataToAllPeers(data: Data) {
        sendData(data: data, peers: mcSession.connectedPeers, mode: .reliable)
    }
    
    func sendData(data: Data, peers: [MCPeerID], mode: MCSessionSendDataMode) {
        do {
            try mcSession.send(data, toPeers: peers, with: mode)
        } catch {
            print("Error sending data: \(error)")
        }
    }

    private func peerConnected(peerID: MCPeerID) {
        if let handler = peerConnectedHandler {
            DispatchQueue.main.async {
                handler(peerID)
            }
        }
        if mcSession.connectedPeers.count == maxNumPeers {
            self.suspend()
        }
    }

    private func peerDisconnected(peerID: MCPeerID) {
        if let handler = peerDisconnectedHandler {
            DispatchQueue.main.async {
                handler(peerID)
            }
        }

        if mcSession.connectedPeers.count < maxNumPeers {
            self.start()
        }
    }

    internal func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            peerConnected(peerID: peerID)
        case .notConnected:
            peerDisconnected(peerID: peerID)
        case .connecting:
            break
        @unknown default:
            fatalError("Unhandled MCSessionState")
        }
    }

    internal func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let handler = peerDataHandler {
            DispatchQueue.main.async {
                handler(data, peerID)
            }
        }
    }

    internal func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    internal func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    internal func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    internal func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let identityValue = info?[MPCSessionConstants.kKeyIdentity] else {
            return
        }
        if identityValue == identityString && mcSession.connectedPeers.count < maxNumPeers {
            browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                             didReceiveInvitationFromPeer peerID: MCPeerID,
                             withContext context: Data?,
                             invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept the invitation only if the number of peers is less than the maximum.
        if self.mcSession.connectedPeers.count < maxNumPeers {
            invitationHandler(true, mcSession)
        }
    }
}

class NearbyInteractionManager: NSObject, ObservableObject {
    private let mpcSession: MPCSession
    private var niSession: NISession?
    private var peerDiscoveryTokens: [MCPeerID: NIDiscoveryToken] = [:]

    @Published var peerDistances: [String: Float] = [:]

    override init() {
        self.mpcSession = MPCSession(service: "halozone", identity: UIDevice.current.name, maxPeers: 1)
        super.init()
        setupHandlers()
        mpcSession.start()
    }

    private func setupHandlers() {
        mpcSession.peerConnectedHandler = { [weak self] peerID in
            print("✅ Peer connected: \(peerID.displayName)")
            self?.prepareAndSendToken(to: peerID)
        }

        mpcSession.peerDisconnectedHandler = { [weak self] peerID in
            print("❌ Peer disconnected: \(peerID.displayName)")
            self?.niSession?.invalidate()
            self?.niSession = nil
        }

        mpcSession.peerDataHandler = { [weak self] data, peerID in
            print("📩 Received token from \(peerID.displayName)")
            guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return }
            self?.peerDiscoveryTokens[peerID] = token
            self?.startNISession(with: token)
        }
    }

    private func prepareAndSendToken(to peerID: MCPeerID) {
        niSession?.invalidate()
        niSession = NISession()
        niSession?.delegate = self

        if let token = niSession?.discoveryToken,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            mpcSession.sendData(data: data, peers: [peerID], mode: .reliable)
            print("📨 Sent discoveryToken to \(peerID.displayName)")
        }
    }

    private func startNISession(with token: NIDiscoveryToken) {
        niSession?.invalidate()
        niSession = NISession()
        niSession?.delegate = self

        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession?.run(config)
        print("🔧 NI session started")
    }
}

extension NearbyInteractionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for obj in nearbyObjects {
            guard let dist = obj.distance else { continue }
            if let match = peerDiscoveryTokens.first(where: { $0.value == obj.discoveryToken }) {
                let peerName = match.key.displayName
                DispatchQueue.main.async {
                    self.peerDistances[peerName] = dist
                }
                print("📏 Distance to \(peerName): \(dist) m")
            }
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("⚠️ NI session invalidated: \(error.localizedDescription)")
    }

    func sessionWasSuspended(_ session: NISession) {
        print("⏸️ NI session suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        print("▶️ NI session resumed")
    }
}
