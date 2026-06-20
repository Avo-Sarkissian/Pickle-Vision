import SwiftUI
import PickleVisionCore

// MARK: - Decorative Court Guide

/// Faint static trapezoid court guide — decorative, pre-calibration, non-interactive.
/// Draws optic-yellow trapezoid + NVZ lines + net line. NOT data-bound to any CourtModel.
private struct DecorativeCourtGuide: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Trapezoid: near edge wider (bottom), far edge narrower (top) — court perspective.
            // Inset from edges so it stays clear of corner chrome.
            let nearLeft  = CGPoint(x: w * 0.10, y: h * 0.88)
            let nearRight = CGPoint(x: w * 0.90, y: h * 0.88)
            let farRight  = CGPoint(x: w * 0.65, y: h * 0.12)
            let farLeft   = CGPoint(x: w * 0.35, y: h * 0.12)

            // NVZ lines: 1/3 from each end along the trapezoid's lateral edges.
            let nvzLeftNear  = lerp(nearLeft,  farLeft,  t: 0.30)
            let nvzRightNear = lerp(nearRight, farRight, t: 0.30)
            let nvzLeftFar   = lerp(farLeft,   nearLeft, t: 0.30)
            let nvzRightFar  = lerp(farRight,  nearRight, t: 0.30)

            // Net: midpoint of the trapezoid.
            let netLeft  = lerp(nearLeft,  farLeft,  t: 0.50)
            let netRight = lerp(nearRight, farRight, t: 0.50)

            ZStack {
                // Court outline (trapezoid).
                Path { p in
                    p.move(to: nearLeft)
                    p.addLine(to: nearRight)
                    p.addLine(to: farRight)
                    p.addLine(to: farLeft)
                    p.closeSubpath()
                }
                .stroke(PVColor.optic, lineWidth: lineWidth)

                // NVZ (kitchen) line — near side.
                Path { p in
                    p.move(to: nvzLeftNear)
                    p.addLine(to: nvzRightNear)
                }
                .stroke(PVColor.optic, lineWidth: max(1, lineWidth - 0.5))

                // NVZ (kitchen) line — far side.
                Path { p in
                    p.move(to: nvzLeftFar)
                    p.addLine(to: nvzRightFar)
                }
                .stroke(PVColor.optic, lineWidth: max(1, lineWidth - 0.5))

                // Net line (slightly heavier).
                Path { p in
                    p.move(to: netLeft)
                    p.addLine(to: netRight)
                }
                .stroke(PVColor.optic, lineWidth: lineWidth + 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @Environment(\.scenePhase) private var scenePhase
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
                CameraPreviewView(camera: camera)
                    .ignoresSafeArea()
                // Faint decorative court guide — static, pre-calibration, behind chrome.
                DecorativeCourtGuide()
                    .opacity(0.28)
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                    .allowsHitTesting(false)
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
                permissionBlocked(restricted: false)
            case .restricted:
                permissionBlocked(restricted: true)
            case .unknown:
                PVColor.feedGradient.ignoresSafeArea()
                ProgressView().tint(PVColor.optic)
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
        .onChange(of: scenePhase) { _, phase in
            // Stop capture while backgrounded (battery + thermal); restart on
            // return — which also re-checks permission if it was granted in Settings.
            switch phase {
            case .active:     camera.start(profile: profile)
            case .background: camera.stop()
            default:          break
            }
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

    // MARK: - Permission Blocked (denied or restricted)

    private func permissionBlocked(restricted: Bool) -> some View {
        ZStack {
            PVColor.feedGradient.ignoresSafeArea()   // dark feed-stand-in background
            VStack(spacing: 16) {
                Image(systemName: "camera.metering.unknown")
                    .font(PVFont.display(44, weight: .regular))
                    .foregroundStyle(PVColor.optic)
                Text(restricted ? "Camera access is restricted" : "Camera access is off")
                    .font(PVFont.screenTitle)
                    .foregroundStyle(PVColor.onDark)
                Text(restricted
                     ? "Camera access is blocked by Screen Time or a device-management profile, so it can't be turned on here. Everything stays on this device."
                     : "Pickle Vision needs the camera to see the court. Everything stays on this device.")
                    .font(PVFont.body)
                    .foregroundStyle(PVColor.onDark.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                // Settings can't fix a restricted (managed) device, so only offer it when denied.
                if !restricted {
                    PrimaryButton("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
