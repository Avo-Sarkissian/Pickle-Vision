import SwiftUI
import PickleVisionCore

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @State private var recStart: Date = .now
    @State private var goCalibrate = false

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
                    bottomRow
                }
                .padding(16)
                .ignoresSafeArea(.container, edges: .horizontal)
                .navigationDestination(isPresented: $goCalibrate) {
                    CalibrationScreen(camera: camera)
                }
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
        .onAppear {
            recStart = .now
            camera.start(profile: profile)
        }
    }

    // MARK: - HUD

    /// Top row: left cluster (REC + format + fps), center Phase-2 placeholder, right cluster (thermal).
    private var topRow: some View {
        HStack(alignment: .top) {
            topLeftCluster
            Spacer(minLength: 12)
            DashedPlaceholder("IN / OUT CALLS · PHASE 2")
                .allowsHitTesting(false)
            Spacer(minLength: 12)
            thermalCluster
        }
    }

    /// Bottom row: score placeholder (left), slo-mo placeholder + Calibrate button (right).
    private var bottomRow: some View {
        HStack(alignment: .bottom) {
            DashedPlaceholder("6 / 3 · SCORE · PHASE 6")
                .allowsHitTesting(false)
            Spacer()
            HStack(spacing: 10) {
                DashedPlaceholder("SLO-MO REPLAY")
                    .allowsHitTesting(false)
                PrimaryButton("Calibrate", systemImage: "scope") {
                    goCalibrate = true
                }
            }
        }
    }

    /// Top-left instrument cluster — REC readout + live format + live fps.
    private var topLeftCluster: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: recStart, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(recStart))
                StatusReadout(
                    label: "REC",
                    value: String(format: "%d:%02d", elapsed / 60, elapsed % 60),
                    dotColor: PVColor.recordRed
                )
            }
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
