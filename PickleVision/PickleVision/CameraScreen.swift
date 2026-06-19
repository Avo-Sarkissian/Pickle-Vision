import SwiftUI
import PickleVisionCore

struct CameraScreen: View {
    @StateObject private var camera = CameraService()

    var body: some View {
        ZStack {
            switch camera.permission {
            case .authorized:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                hud
            case .denied:
                permissionDenied
            case .unknown:
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var hud: some View {
        VStack {
            HStack(spacing: 10) {
                pill(camera.selectedFormatDescription)
                pill("\(camera.measuredFPS) fps")
                if camera.thermal.shouldWarn, let msg = camera.thermal.message {
                    pill(msg, warning: true)
                }
                Spacer()
            }
            .padding()
            Spacer()
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown").font(.largeTitle)
            Text("Camera access is off").font(.headline)
            Text("Pickle Vision needs the camera to see the court.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func pill(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(warning ? Color.orange.opacity(0.9) : Color.black.opacity(0.55))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
