import Foundation
import MultipeerConnectivity
import NearbyInteraction
import UIKit

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
