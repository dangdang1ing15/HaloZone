import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine

// MARK: - Peer 모델
struct PeerInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let peerID: MCPeerID
    var distance: Float?
    var message: String?
}

class NearbyInteractionCoordinator: NSObject, ObservableObject {
    // MARK: - Published
    @Published var peers: [PeerInfo] = []

    // MARK: - MPC & NI
    private var mpcSession: MPCSession?
    private var niSession: NISession?
    private var peerDiscoveryTokens: [MCPeerID: NIDiscoveryToken] = [:]
    private var sharedTokens: Set<MCPeerID> = []
    private var connectedPeers: Set<MCPeerID> = []
    private lazy var identity: String = deviceHash

    // MARK: - 차단 및 저장 메시지
    private var blockedPeers: Set<String> = []
    private let blockedPeersKey = "blockedPeers"
    private let savedMessagesKey = "savedMessages"

    // MARK: - Init
    override init() {
        super.init()
        loadBlockedPeers()
        loadSavedMessages()
        startup()
    }

    // MARK: - 고유 해시 생성
    private var deviceHash: String {
        if let existing = UserDefaults.standard.string(forKey: "deviceHash") {
            return existing
        } else {
            let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            let newHash = String((0..<4).compactMap { _ in characters.randomElement() })
            UserDefaults.standard.set(newHash, forKey: "deviceHash")
            return newHash
        }
    }

    // MARK: - Startup
    func startup() {
        print("📛 My identity: \(identity)")
        print("🟢 Starting up NI + MPC")

        niSession = NISession()
        niSession?.delegate = self
        startMPC()
    }

    func startMPC() {
        if mpcSession == nil {
            mpcSession = MPCSession(service: "halozone", identity: identity, maxPeers: 4)

            mpcSession?.peerConnectedHandler = handlePeerConnected
            mpcSession?.peerDataHandler = handleDataReceived
            mpcSession?.peerDisconnectedHandler = handlePeerDisconnected
        }
        mpcSession?.invalidate()
        mpcSession?.start()
    }

    // MARK: - Peer 연결 처리
    func handlePeerConnected(_ peer: MCPeerID) {
        if blockedPeers.contains(peer.displayName) {
            print("🚫 Blocked peer tried to connect: \(peer.displayName)")
            mpcSession?.invalidate()
            return
        }

        connectedPeers.insert(peer)

        if let token = niSession?.discoveryToken, !sharedTokens.contains(peer) {
            shareMyDiscoveryToken(to: peer, token: token)
        }

        print("🔗 Peer connected: \(peer.displayName)")

        let info = PeerInfo(id: peer.displayName, name: peer.displayName, peerID: peer, distance: nil, message: nil)
        if !peers.contains(where: { $0.id == info.id }) {
            DispatchQueue.main.async {
                self.peers.append(info)
            }
        }
    }

    func handlePeerDisconnected(_ peer: MCPeerID) {
        print("❌ Peer disconnected: \(peer.displayName)")
        connectedPeers.remove(peer)
        sharedTokens.remove(peer)
        peerDiscoveryTokens.removeValue(forKey: peer)

        DispatchQueue.main.async {
            self.peers.removeAll(where: { $0.id == peer.displayName })
        }
    }

    // MARK: - Token 공유
    func shareMyDiscoveryToken(to peer: MCPeerID, token: NIDiscoveryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        mpcSession?.sendData(data: data, peers: [peer], mode: .reliable)
        sharedTokens.insert(peer)
    }

    // MARK: - 데이터 수신
    func handleDataReceived(_ data: Data, from peer: MCPeerID) {
        guard let text = String(data: data, encoding: .utf8) else {
            print("⚠️ Unknown data format received")
            return
        }

        if text.hasPrefix("MSG:") {
            let message = String(text.dropFirst(4))
            print("📥 Received MSG from \(peer.displayName): \(message)")
            
            if let index = peers.firstIndex(where: { $0.id == peer.displayName }) {
                DispatchQueue.main.async {
                    self.peers[index].message = message
                }
            }
            saveMessage(peer.displayName, message: message)
            blockPeer(peer.displayName)
            sendAck(to: peer)

        } else if text.hasPrefix("ACK:") {
            print("✅ ACK received from \(peer.displayName)")
            blockPeer(peer.displayName)
            disconnectSessions()

        } else if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
            peerDidShareDiscoveryToken(peer: peer, token: token)
        }
    }

    // MARK: - ACK 전송
    func sendAck(to peer: MCPeerID) {
        let ackMessage = "ACK:\(identity)"
        guard let data = ackMessage.data(using: .utf8) else { return }
        mpcSession?.sendData(data: data, peers: [peer], mode: .reliable)
    }

    func peerDidShareDiscoveryToken(peer: MCPeerID, token: NIDiscoveryToken) {
        peerDiscoveryTokens[peer] = token
        print("📩 Received discoveryToken from \(peer.displayName)")

        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession?.run(config)
    }

    // MARK: - 거리 업데이트
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for obj in nearbyObjects {
            guard let peer = peerDiscoveryTokens.first(where: { $0.value == obj.discoveryToken })?.key,
                  let distance = obj.distance else { continue }

            if let index = peers.firstIndex(where: { $0.id == peer.displayName }) {
                DispatchQueue.main.async {
                    self.peers[index].distance = distance
                }
            }
        }
    }

    // MARK: - 메시지 전송
    func sendMessage(_ message: String, to peerID: MCPeerID) {
        let formatted = "MSG:\(message)"
        guard let data = formatted.data(using: .utf8) else { return }
        mpcSession?.sendData(data: data, peers: [peerID], mode: .reliable)
        print("📤 Sent message to \(peerID.displayName): \(message)")
    }

    // MARK: - 세션 끊기
    func disconnectSessions() {
        niSession?.invalidate()
        mpcSession?.invalidate()
    }

    // MARK: - 차단 관리
    func blockPeer(_ peerID: String) {
        blockedPeers.insert(peerID)
        UserDefaults.standard.set(Array(blockedPeers), forKey: blockedPeersKey)
    }

    func loadBlockedPeers() {
        if let list = UserDefaults.standard.array(forKey: blockedPeersKey) as? [String] {
            blockedPeers = Set(list)
        }
    }

    // MARK: - 메시지 저장/로드
    func saveMessage(_ peerID: String, message: String) {
        var messages = UserDefaults.standard.dictionary(forKey: savedMessagesKey) as? [String: String] ?? [:]
        messages[peerID] = message
        UserDefaults.standard.set(messages, forKey: savedMessagesKey)
    }

    func loadSavedMessages() {
        if let saved = UserDefaults.standard.dictionary(forKey: savedMessagesKey) as? [String: String] {
            for (peerID, message) in saved {
                let peerInfo = PeerInfo(id: peerID, name: peerID, peerID: MCPeerID(displayName: peerID), distance: nil, message: message)
                peers.append(peerInfo)
            }
        }
    }

    // MARK: - 디버그 초기화
    func resetConnections() {
        blockedPeers.removeAll()
        UserDefaults.standard.removeObject(forKey: blockedPeersKey)
        UserDefaults.standard.removeObject(forKey: savedMessagesKey)

        peers.removeAll()
        mpcSession?.invalidate()
        niSession?.invalidate()

        startup()
    }
}

extension NearbyInteractionCoordinator: NISessionDelegate {
    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("⚠️ NI session invalidated: \(error.localizedDescription)")
        startup()
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        if reason == .peerEnded {
            print("🔄 Peer ended → restarting")
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
