import SwiftUI

struct VersionGateView: View {
    var body: some View {
        if #available(iOS 16.0, *) {
            HaloMainView() // 메인 기능 뷰
        } else {
            VStack(spacing: 16) {
                Text("iOS 16 이상이 필요합니다.")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text("설정 > 일반 > 소프트웨어 업데이트에서 최신 버전으로 업데이트해주세요.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            }
            .padding()
        }
    }
}
