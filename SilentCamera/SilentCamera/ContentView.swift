import SwiftUI
import AVFoundation

/// Root view — shows camera or a permission-denied message.
struct ContentView: View {

    @StateObject private var camera = CameraManager()

    var body: some View {
        Group {
            switch camera.authorizationStatus {
            case .authorized:
                CameraView()
            case .denied, .restricted:
                permissionDeniedView
            default:
                // Waiting for user authorization dialog
                Color.black
                    .ignoresSafeArea()
                    .onAppear { camera.checkAuthorization() }
            }
        }
    }

    private var permissionDeniedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.6))

                Text("카메라 접근 권한이 필요합니다")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("설정 → 개인 정보 보호 → 카메라에서\n이 앱의 카메라 접근을 허용해 주세요.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    ContentView()
}
