import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine

class NearbyInteractionCoordinator: NSObject, ObservableObject {
    // MARK: - Published
    @Published var peerDistance: Float? = nil
    @Published var peerName: String? = nil

    // MARK: - MPC & NI
    private var mpcSession: MPCSession?
    private var niSession: NISession?
    private var peerDiscoveryToken: NIDiscoveryToken?
    private var connectedPeer: MCPeerID?
    private var sharedToken = false

    private let serviceType = "halozone"
    private let identity = UIDevice.current.name

    // 거리 해제 임계점 처리용 상태
    private var wasPreviouslyNearby: Bool = false
    private let nearbyThreshold: Float = 2.0

    override init() {
        super.init()
        startup()
    }

    func startup() {
        print("🟢 Starting up NI + MPC")

        niSession = NISession()
        niSession?.delegate = self
        sharedToken = false

        if connectedPeer != nil, let token = niSession?.discoveryToken {
            shareDiscoveryToken(token)
            if let peerToken = peerDiscoveryToken {
                let config = NINearbyPeerConfiguration(peerToken: peerToken)
                niSession?.run(config)
            }
        } else {
            startMPC()
        }
    }

    func startMPC() {
        mpcSession = MPCSession(service: serviceType, identity: identity, maxPeers: 1)
        mpcSession?.peerConnectedHandler = { [weak self] peer in
            self?.handlePeerConnected(peer)
        }
        mpcSession?.peerDataHandler = { [weak self] data, peer in
            self?.handleDataReceived(data, from: peer)
        }
        mpcSession?.peerDisconnectedHandler = { [weak self] peer in
            self?.handlePeerDisconnected(peer)
        }
        mpcSession?.start()
    }

    func handlePeerConnected(_ peer: MCPeerID) {
        guard let token = niSession?.discoveryToken else { return }
        print("🔗 Peer connected: \(peer.displayName)")
        connectedPeer = peer
        peerName = peer.displayName

        if !sharedToken {
            shareDiscoveryToken(token)
        }
    }

    func handlePeerDisconnected(_ peer: MCPeerID) {
        print("❌ Peer disconnected: \(peer.displayName)")
        if connectedPeer == peer {
            connectedPeer = nil
            sharedToken = false
        }
        startup()
    }

    func shareDiscoveryToken(_ token: NIDiscoveryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        mpcSession?.sendDataToAllPeers(data: data)
        sharedToken = true
    }

    func handleDataReceived(_ data: Data, from peer: MCPeerID) {
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return }
        if connectedPeer != peer { return }
        peerDiscoveryToken = token
        print("📩 Received discoveryToken from \(peer.displayName)")

        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession?.run(config)
    }
}

extension NearbyInteractionCoordinator: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerToken = peerDiscoveryToken else { return }
        guard let obj = nearbyObjects.first(where: { $0.discoveryToken == peerToken }),
              let distance = obj.distance else { return }

        // ✅ 이전 상태와 현재 상태 비교하여 노이즈 방지 후 연결 해제
        if wasPreviouslyNearby && distance >= nearbyThreshold + 0.3 {
            print("📡 거리 초과 → 연결 해제: \\(distance)m")

            peerDistance = nil
            peerDiscoveryToken = nil
            connectedPeer = nil
            sharedToken = false
            wasPreviouslyNearby = false

            session.invalidate()
            mpcSession?.invalidate()
            mpcSession = nil

            // ✅ 여기가 핵심!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startup()
            }

            return
        }

        // 상태 업데이트
        wasPreviouslyNearby = distance < nearbyThreshold

        DispatchQueue.main.async {
            self.peerDistance = distance
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("⚠️ NI session invalidated: \(error.localizedDescription)")
        startup()
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        if reason == .peerEnded {
            print("🔄 Peer ended → restarting")
            peerDiscoveryToken = nil
            startup()
        } else if reason == .timeout, let config = session.configuration {
            session.run(config)
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        print("⏸️ NI session suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        print("▶️ NI session resumed")
        if let config = session.configuration {
            session.run(config)
        } else {
            startup()
        }
    }
}
