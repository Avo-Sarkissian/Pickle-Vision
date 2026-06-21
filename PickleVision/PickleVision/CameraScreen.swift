import SwiftUI
import PickleVisionCore

// MARK: - Decorative Court Guide

/// Faint static trapezoid court guide - decorative, pre-calibration, non-interactive.
/// Draws optic-yellow trapezoid + NVZ lines + net line. NOT data-bound to any CourtModel.
private struct DecorativeCourtGuide: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Trapezoid: near edge wider (bottom), far edge narrower (top) - court perspective.
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

                // NVZ (kitchen) line - near side.
                Path { p in
                    p.move(to: nvzLeftNear)
                    p.addLine(to: nvzRightNear)
                }
                .stroke(PVColor.optic, lineWidth: max(1, lineWidth - 0.5))

                // NVZ (kitchen) line - far side.
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
    /// Set to the recording-start Date when recording begins; nil when idle.
    @State private var recStart: Date? = nil
    @State private var goCalibrate = false

    private let profile: CaptureProfile
    private let court: CourtModel?
    private let courtName: String?
    private let courtID: UUID?

    init(profile: CaptureProfile = .auto, court: CourtModel? = nil, courtName: String? = nil, courtID: UUID? = nil) {
        self.profile = profile
        self.court = court
        self.courtName = courtName
        self.courtID = courtID
    }

    var body: some View {
        ZStack {
            switch camera.permission {
            case .authorized:
                CameraPreviewView(camera: camera)
                    .ignoresSafeArea()
                // Calibrated overlay when a court is present; decorative guide otherwise.
                if let court {
                    CourtOverlay(model: court, imageSize: camera.imageSize)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                } else {
                    DecorativeCourtGuide()
                        .opacity(0.28)
                        .padding(.horizontal, 80).padding(.vertical, 40)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
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
        // Note: we intentionally do NOT stop the session on disappear - pushing
        // the Calibration screen reuses the same session (and its frame feed).
        .onAppear {
            camera.start(profile: profile)
        }
        .onChange(of: camera.isRecording) { _, isNowRecording in
            // Capture start time when recording begins; clear it when recording stops.
            recStart = isNowRecording ? .now : nil
        }
        .onChange(of: scenePhase) { _, phase in
            // Stop capture while backgrounded (battery + thermal); restart on
            // return - which also re-checks permission if it was granted in Settings.
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
            VStack(spacing: 4) {
                DashedPlaceholder("IN / OUT CALLS · PHASE 2")
                    .allowsHitTesting(false)
                if let name = courtName {
                    InstrumentPill(name, tint: PVColor.optic)
                    Text("Saved map - re-tap with Calibrate if the camera moved")
                        .font(PVFont.mono(9))
                        .foregroundStyle(PVColor.onDarkDim)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 12)
            thermalCluster
        }
    }

    /// Bottom row: score placeholder (left), record toggle + slo-mo placeholder + Calibrate button (right).
    private var bottomRow: some View {
        HStack(alignment: .bottom) {
            DashedPlaceholder("6 / 3 · SCORE · PHASE 6")
                .allowsHitTesting(false)
            Spacer()
            HStack(spacing: 10) {
                Button {
                    if camera.isRecording { camera.stopRecording() }
                    else if let courtID { camera.startRecording(courtID: courtID) }
                } label: {
                    Image(systemName: camera.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(PVFont.display(34))
                        .foregroundStyle(camera.isRecording ? PVColor.recordRed : PVColor.onDark)
                }
                .disabled(courtID == nil)   // generic court-less session cannot record a bound clip
                .accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
                DashedPlaceholder("SLO-MO REPLAY")
                    .allowsHitTesting(false)
                PrimaryButton("Calibrate", systemImage: "scope") {
                    goCalibrate = true
                }
            }
        }
    }

    /// Top-left instrument cluster - REC readout + live format + live fps.
    /// REC elapsed only counts while `camera.isRecording`; idle shows "--:--".
    private var topLeftCluster: some View {
        HStack(spacing: 8) {
            if let start = recStart {
                // Recording active: drive elapsed from the captured start time.
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(start))
                    StatusReadout(
                        label: "REC",
                        value: String(format: "%d:%02d", elapsed / 60, elapsed % 60),
                        dotColor: PVColor.recordRed
                    )
                }
            } else {
                // Idle: show placeholder so the HUD item stays in place.
                StatusReadout(
                    label: "REC",
                    value: "--:--",
                    dotColor: PVColor.recordRed
                )
            }
            InstrumentPill(camera.selectedFormatDescription)
            InstrumentPill("\(camera.measuredFPS) fps")
        }
    }

    /// Top-right - amber thermal pill, only when the policy says to warn.
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

// MARK: - Preview

#Preview("CameraScreen - with calibrated court overlay") {
    // Build a CourtModel from normalized [0,1] corners (same pattern as CourtOverlay preview).
    // Order: [nearLeft, nearRight, farRight, farLeft] - near (wide) at bottom, far (narrow) at top.
    let profile = CourtProfile.make(layout: .regulationPickleball)
    let imgCorners = [
        CGPoint(x: 0.18, y: 0.82),  // nearLeft
        CGPoint(x: 0.82, y: 0.82),  // nearRight
        CGPoint(x: 0.64, y: 0.30),  // farRight
        CGPoint(x: 0.36, y: 0.30),  // farLeft
    ]
    let model: CourtModel? = Homography(source: imgCorners, destination: profile.calibrationCorners)
        .map { CourtModel(profile: profile, homography: $0) }

    return ZStack {
        PVColor.feedGradient.ignoresSafeArea()
        if let model {
            // Simulate the overlay on a feed-gradient stand-in (camera not available in preview).
            let imageSize = CGSize(width: 1280, height: 720)
            CourtOverlay(model: model, imageSize: imageSize)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
    .overlay(alignment: .top) {
        if model != nil {
            VStack(spacing: 4) {
                InstrumentPill("Riverside - Court 3", tint: PVColor.optic)
                Text("Saved map - re-tap with Calibrate if the camera moved")
                    .font(PVFont.mono(9))
                    .foregroundStyle(PVColor.onDarkDim)
            }
            .padding(.top, 16)
        }
    }
    .frame(width: 560, height: 315)  // landscape, like the live camera
}
