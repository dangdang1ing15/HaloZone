import SwiftUI

struct MessageLogView: View {
    @State private var messages: [ReceivedMessage] = []

    var body: some View {
        List(messages.indices, id: \.self) { index in
            let msg = messages[index]
            VStack(alignment: .leading) {
                Text("📥 \(msg.message)")
                    .font(.body)
                Text("👤 \(msg.sender)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("⏰ \(msg.receivedAt)")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("📜 메시지 로그")
        .onAppear {
            loadMessages()
        }
    }

    func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: "savedMessages"),
           let decoded = try? JSONDecoder().decode([ReceivedMessage].self, from: data) {
            messages = decoded
        }
    }
}
