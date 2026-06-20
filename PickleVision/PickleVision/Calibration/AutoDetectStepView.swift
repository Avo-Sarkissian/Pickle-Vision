import SwiftUI
import PickleVisionCore

// MARK: - AutoDetectStepView

/// Step 2 — AUTO-DETECT.
/// Switches on `model.flow.autoDetect` to render four states:
///   .idle    → "Auto-detect" + "Calibrate manually instead"
///   .finding → scan band on canvas + spinner + "Calibrate manually instead"
///   .found   → "Court found" pill (canvas), layout chips, Fine-tune button
///   .failed  → centered failure card with Drag + Try-again buttons
///
/// Canvas overlays (scan band, court outline, pill) are in AutoDetectCanvasOverlay
/// and injected by CalibrationWizardView.canvasArea for the .detect step.
struct AutoDetectStepView: View {
    @ObservedObject var model: CalibrationModel

    var body: some View {
        Group {
            switch model.flow.autoDetect {
            case .idle:
                idleRail
            case .finding:
                findingRail
            case .found:
                foundRail
            case .failed:
                failedRail
            }
        }
        .onAppear {
            // Auto-start the stub when entering .detect so the finding→failed
            // flow is immediately visible. Manual is always reachable in every sub-state.
            if model.flow.autoDetect == .idle {
                model.runAutoDetectStub()
            }
        }
    }

    // MARK: - .idle rail

    private var idleRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel

            Text("Tap Auto-detect and the app will try to find the court lines.")
                .font(PVFont.mono(9, weight: .regular))
                .foregroundStyle(PVColor.onDarkDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            PrimaryButton("Auto-detect") {
                model.runAutoDetectStub()
            }
            .padding(.bottom, 10)

            SecondaryButton("Calibrate manually instead") {
                model.flow.calibrateManually()
            }

            Spacer(minLength: 12)
        }
        .padding(16)
    }

    // MARK: - .finding rail

    private var findingRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel

            HStack(spacing: 10) {
                ProgressView()
                    .tint(PVColor.optic)
                    .scaleEffect(0.9)
                Text("Finding the court\u{2026}")
                    .font(PVFont.ui(14, weight: .regular))
                    .foregroundStyle(PVColor.onDark)
            }
            .padding(.bottom, 18)

            SecondaryButton("Calibrate manually instead") {
                model.flow.calibrateManually()
            }

            Spacer(minLength: 12)
        }
        .padding(16)
    }

    // MARK: - .found rail

    private var foundRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel

            Text("Confirm the layout, or drag any corner.")
                .font(PVFont.mono(9, weight: .regular))
                .foregroundStyle(PVColor.onDarkDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            SegmentedChips(layoutChips, selection: layoutBinding)
                .padding(.bottom, 14)

            PrimaryButton("Fine-tune \u{2192}") {
                model.flow.advance()
            }
            .padding(.bottom, 8)

            SecondaryButton("Calibrate manually instead") {
                model.flow.calibrateManually()
            }

            Spacer(minLength: 12)
        }
        .padding(16)
    }

    // MARK: - .failed rail

    private var failedRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel

            Spacer(minLength: 0)

            failedCard
                .frame(maxWidth: .infinity)

            Spacer(minLength: 12)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var stepLabel: some View {
        Text("AUTO-DETECT")
            .font(PVFont.mono(10, weight: .semibold))
            .tracking(PVFont.labelTracking)
            .foregroundStyle(PVColor.monoLabel)
            .padding(.bottom, 14)
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn\u{2019}t find the court")
                .font(PVFont.ui(14, weight: .semibold))
                .foregroundStyle(PVColor.onDark)
                .fixedSize(horizontal: false, vertical: true)

            Text("Faded paint or odd lighting can hide the lines. Drag the four corners yourself \u{2014} it\u{2019}s the guaranteed path.")
                .font(PVFont.mono(9, weight: .regular))
                .foregroundStyle(PVColor.onDarkDim)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton("Drag the corners") {
                model.flow.dropToManual()
            }
            .padding(.top, 4)

            SecondaryButton("Try auto again") {
                model.runAutoDetectStub()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PVColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(PVColor.cardBorder, lineWidth: 1)
                )
        )
    }

    private let layoutChips: [SegmentedChip] = [
        SegmentedChip(id: CourtLayout.regulationPickleball.rawValue,
                      title: "Pickleball", trailing: "20\u{d7}44"),
        SegmentedChip(id: CourtLayout.tennisFrontBox.rawValue,
                      title: "Tennis box", trailing: "27\u{d7}42"),
        SegmentedChip(id: CourtLayout.custom.rawValue,
                      title: "Custom", trailing: "set ft"),
    ]

    /// Bridges `model.flow.layout: CourtLayout` to the String-keyed SegmentedChips.
    private var layoutBinding: Binding<String> {
        Binding(
            get: { model.flow.layout.rawValue },
            set: { newValue in
                if let layout = CourtLayout(rawValue: newValue) {
                    model.flow.layout = layout
                    if layout == .custom {
                        model.showCustomDims = true
                    }
                }
            }
        )
    }
}

// MARK: - AutoDetectCanvasOverlay

/// Canvas content for the .detect wizard step.
/// .finding → animated scan band
/// .found   → "Court found" pill + CourtOverlay outline
/// .idle / .failed → nothing extra
struct AutoDetectCanvasOverlay: View {
    @ObservedObject var model: CalibrationModel

    var body: some View {
        switch model.flow.autoDetect {
        case .idle:
            EmptyView()
        case .finding:
            ScanBandView()
        case .found:
            foundOverlay
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var foundOverlay: some View {
        // "Court found" pill — top-left (no percentage — honesty rule)
        VStack {
            HStack {
                InstrumentPill(systemImage: "circle.fill", "Court found", tint: PVColor.optic)
                    .padding(12)
                Spacer()
            }
            Spacer()
        }

        // Court outline via shared CourtOverlay
        if let courtModel = model.flow.courtModel {
            CourtOverlay(model: courtModel, imageSize: model.frozenSize)
        }
    }
}

// MARK: - ScanBandView

/// Animated optic-yellow gradient strip that sweeps top-to-bottom over the frozen frame.
private struct ScanBandView: View {
    @State private var offsetFraction: CGFloat = -0.12   // starts just above top

    var body: some View {
        GeometryReader { geo in
            let bandH = geo.size.height * 0.12
            let totalTravel = geo.size.height + bandH
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: PVColor.optic.opacity(0),    location: 0),
                            .init(color: PVColor.optic.opacity(0.45), location: 0.5),
                            .init(color: PVColor.optic.opacity(0),    location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: geo.size.width, height: bandH)
                .offset(y: offsetFraction * totalTravel)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        offsetFraction = 1.0
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - runAutoDetectStub (CalibrationModel extension)

extension CalibrationModel {
    /// v1 stub for the (Plan 3.5) detector. Simulates a short scan, then resolves
    /// to .failed so the user lands on the guaranteed manual path. Plan 3.5 will
    /// replace the body with a real detector that may resolve to .found(corners).
    func runAutoDetectStub() {
        flow.startAutoDetect()          // autoDetect = .finding
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.flow.autoDetect == .finding else { return }
            self.flow.resolveAutoDetect(.failed, detectedCorners: nil)
        }
    }
}

// MARK: - Previews

#Preview("AutoDetect — idle") {
    ZStack {
        PVColor.rail.ignoresSafeArea()
        AutoDetectStepView(model: CalibrationModel(camera: CameraService(),
                                                   flow: CalibrationFlow(step: .detect)))
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}

#Preview("AutoDetect — finding") {
    var flow = CalibrationFlow(step: .detect)
    flow.startAutoDetect()
    return ZStack {
        PVColor.rail.ignoresSafeArea()
        AutoDetectStepView(model: CalibrationModel(camera: CameraService(), flow: flow))
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}

#Preview("AutoDetect — found") {
    var flow = CalibrationFlow(step: .detect)
    flow.resolveAutoDetect(.found, detectedCorners: CalibrationDraft.defaultCorners())
    return ZStack {
        PVColor.rail.ignoresSafeArea()
        AutoDetectStepView(model: CalibrationModel(camera: CameraService(), flow: flow))
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}

#Preview("AutoDetect — failed") {
    var flow = CalibrationFlow(step: .detect)
    flow.resolveAutoDetect(.failed, detectedCorners: nil)
    return ZStack {
        PVColor.rail.ignoresSafeArea()
        AutoDetectStepView(model: CalibrationModel(camera: CameraService(), flow: flow))
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}
