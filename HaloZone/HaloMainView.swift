import SwiftUI

struct HaloMainView: View {
    @StateObject private var coordinator = NearbyInteractionCoordinator()
    @State private var autoSendEnabled: Bool = false
    @State private var commonMessage: String = ""

    var body: some View {
        NavigationView {
            VStack {
                List {
                    // 📨 메시지 설정 영역 내에 토글 추가
                    Section(header: Text("📨 보낼 메시지")) {
                        TextField("공통 메시지를 입력하세요", text: $commonMessage)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.vertical, 4)

                        Toggle(isOn: $autoSendEnabled) {
                            Label("자동 전송", systemImage: autoSendEnabled ? "bolt.fill" : "bolt.slash")
                                .foregroundColor(autoSendEnabled ? .green : .gray)
                        }
                    }


                    // 연결된 기기 리스트
                    Section(header: Text("🔗 연결된 기기")) {
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

                                // 📤 공통 메시지 보내기 버튼
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        if !commonMessage.isEmpty {
                                            coordinator.sendMessage(commonMessage, to: peer.peerID)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "paperplane.circle.fill")
                                            Text("보내기")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(commonMessage.isEmpty)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())

                // 📜 메시지 로그 보기 버튼 (리스트 하단)
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
            }
            .navigationTitle("🟡 HaloZone")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("연결 초기화") {
                        coordinator.resetConnections()
                    }
                }
            }
            .onChange(of: commonMessage) { newValue in
                coordinator.commonMessage = newValue
            }
            .onChange(of: autoSendEnabled) { newValue in
                coordinator.autoSendEnabled = newValue
            }

        }
    }
}
