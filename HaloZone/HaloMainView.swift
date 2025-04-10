import SwiftUI

struct HaloMainView: View {
    @StateObject private var coordinator = NearbyInteractionCoordinator()
    @State private var messageInputs: [String: String] = [:]

    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("연결된 기기")) {
                        ForEach(coordinator.peers) { peer in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("📱 \(peer.name)")
                                    .font(.headline)
                                
                                if let distance = peer.distance {
                                    Text(String(format: "📏 거리: %.2f m", distance))
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                } else {
                                    Text("📡 거리 정보 없음")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                if let message = peer.message {
                                    Text("💬 \(message)")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("💬 메시지 없음")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    TextField("메시지 입력", text: Binding(
                                        get: { messageInputs[peer.id] ?? "" },
                                        set: { messageInputs[peer.id] = $0 }
                                    ))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(minWidth: 100)
                                    
                                    Button(action: {
                                        if let message = messageInputs[peer.id], !message.isEmpty {
                                            coordinator.sendMessage(message, to: peer.peerID)
                                            messageInputs[peer.id] = ""
                                        }
                                    }) {
                                        Image(systemName: "paperplane.fill")
                                    }
                                    .disabled((messageInputs[peer.id] ?? "").isEmpty)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                // 하단 버튼 영역
                NavigationLink(destination: MessageLogView()) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("메시지 로그 보기")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            
                .navigationTitle("🟡 HaloZone")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("초기화") {
                            coordinator.resetConnections()
                            messageInputs.removeAll()
                        }
                    }
        
                }
            }
        }
    }
}
