import SwiftUI
import PickleVisionCore

struct CameraScreen: View {
    @StateObject private var camera = CameraService()

    private let profile: CaptureProfile

    init(profile: CaptureProfile = .auto) {
        self.profile = profile
    }

    var body: some View {
        ZStack {
            switch camera.permission {
            case .authorized:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                VStack {
                    topRow
                    Spacer()
                    NavigationLink {
                        CalibrationScreen(camera: camera)
                    } label: {
                        Label("Calibrate court", systemImage: "scope")
                            .font(PVFont.ui(14, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 30)
                }
                .padding(16)
                .ignoresSafeArea(.container, edges: .horizontal)
            case .denied:
                permissionDenied
            case .unknown:
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .lockOrientation(.landscape)
        // Note: we intentionally do NOT stop the session on disappear — pushing
        // the Calibration screen reuses the same session (and its frame feed).
        .onAppear { camera.start(profile: profile) }
    }

    // MARK: - HUD

    /// Top row: left cluster (REC + format + fps) and right cluster (thermal, conditional).
    private var topRow: some View {
        HStack(alignment: .top) {
            topLeftCluster
            Spacer(minLength: 12)
            thermalCluster
        }
    }

    /// Top-left instrument cluster — REC readout + live format + live fps.
    private var topLeftCluster: some View {
        HStack(spacing: 8) {
            StatusReadout(label: "REC", value: "12:04", dotColor: PVColor.recordRed)
            InstrumentPill(camera.selectedFormatDescription)
            InstrumentPill("\(camera.measuredFPS) fps")
        }
    }

    /// Top-right — amber thermal pill, only when the policy says to warn.
    @ViewBuilder private var thermalCluster: some View {
        if camera.thermal.shouldWarn, let msg = camera.thermal.message {
            InstrumentPill(systemImage: "thermometer.medium", msg, tint: PVColor.amber)
        }
    }

    // MARK: - Permission Denied

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
}
