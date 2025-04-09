import Foundation
import MultipeerConnectivity

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
    private let localPeerID: MCPeerID
    private let mcSession: MCSession
    private let mcAdvertiser: MCNearbyServiceAdvertiser
    private var mcBrowser: MCNearbyServiceBrowser?

    init(service: String, identity: String, maxPeers: Int) {
        self.serviceString = service
        self.identityString = identity
        self.maxNumPeers = maxPeers
        self.localPeerID = MCPeerID(displayName: identity)  // ✅ 수정된 부분

        self.mcSession = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.mcAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: [MPCSessionConstants.kKeyIdentity: identity], serviceType: serviceString)
        self.mcBrowser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceString)

        super.init()

        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcBrowser?.delegate = self
    }

    func start() {
        print("📡 MPCSession start — identity: \(identityString)")
        mcAdvertiser.startAdvertisingPeer()
        if mcBrowser == nil {
            mcBrowser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceString)
            mcBrowser?.delegate = self
        }
        mcBrowser?.startBrowsingForPeers()
    }

    func suspend() {
        mcAdvertiser.stopAdvertisingPeer()
        mcBrowser?.stopBrowsingForPeers()
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
            print("⚠️ Error sending data: \(error)")
        }
    }

    private func peerConnected(peerID: MCPeerID) {
        print("✅ Connected to peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.peerConnectedHandler?(peerID)
        }
        if mcSession.connectedPeers.count == maxNumPeers {
            self.suspend()
        }
    }

    private func peerDisconnected(peerID: MCPeerID) {
        print("❌ Disconnected from peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.peerDisconnectedHandler?(peerID)
        }

        if mcSession.connectedPeers.count < maxNumPeers {
            self.start()
        }
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("🔗 MCSessionState: connected to \(peerID.displayName)")
            peerConnected(peerID: peerID)
        case .notConnected:
            print("🔌 MCSessionState: not connected to \(peerID.displayName)")
            peerDisconnected(peerID: peerID)
        case .connecting:
            print("⏳ MCSessionState: connecting to \(peerID.displayName)")
        @unknown default:
            fatalError("Unhandled MCSessionState")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.peerDataHandler?(data, peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let identityValue = info?[MPCSessionConstants.kKeyIdentity] else { return }
        print("🔍 Found peer: \(peerID.displayName), identity: \(identityValue)")

        if identityValue != identityString && mcSession.connectedPeers.count < maxNumPeers {
            print("📨 Sending invitation to: \(peerID.displayName)")
            browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
        } else {
            print("🚫 Skipping peer (self or full)")
        }
    }


    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📥 Received invitation from: \(peerID.displayName)")
        if mcSession.connectedPeers.count < maxNumPeers {
            invitationHandler(true, mcSession)
        } else {
            print("🚫 Invitation rejected (max peers reached)")
            invitationHandler(false, nil)
        }
    }
}
