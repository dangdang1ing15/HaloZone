import SwiftUI

struct HaloMainView: View {
    @StateObject private var coordinator = NearbyInteractionCoordinator()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("🟡 HaloZone")
                    .font(.largeTitle)
                    .bold()

                if let name = coordinator.peerName {
                    Text("📱 연결된 기기: \(name)")
                        .font(.headline)
                } else {
                    Text("🔍 피어 탐색 중...")
                        .foregroundColor(.gray)
                }

                if let distance = coordinator.peerDistance {
                    Text(String(format: "📏 거리: %.2f m", distance))
                        .font(.title2)
                        .padding()
                        .background(distance < 2.0 ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                        .cornerRadius(12)
                } else {
                    Text("거리 정보 없음")
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    HaloMainView()
}
