import SwiftUI
import Combine
import PickleVisionCore

// MARK: - CalibrationModel

/// View-model for the calibration wizard. Owns the `CalibrationFlow` state
/// machine, the frozen CGImage, and the `CameraService`. Step views receive
/// `@ObservedObject var model: CalibrationModel` and mutate `model.flow`
/// directly (flow is a `@Published` struct so every mutation triggers diffing).
@MainActor final class CalibrationModel: ObservableObject {
    @Published var flow: CalibrationFlow
    @Published var frozen: CGImage?
    @Published var frozenSize: CGSize = .zero
    @Published var venueName: String = "My Court"
    @Published var saveError: String?
    @Published var showCustomDims: Bool = false
    @Published var showUltraWide: Bool = false

    let camera: CameraService
    private let store: CalibrationStore
    private var freezeSink: AnyCancellable?

    init(camera: CameraService,
         flow: CalibrationFlow = CalibrationFlow(),
         venueName: String = "My Court") {
        self.camera = camera
        self.flow = flow
        self.venueName = venueName
        self.store = CalibrationStore(
            directory: URL.documentsDirectory.appendingPathComponent("calibrations")
        )
    }

    // MARK: - Freeze

    /// Captures a frozen frame. If a frame is already available, uses it
    /// immediately. Otherwise subscribes to the first frame that arrives.
    /// (Preserves "capture first frame on freeze" behavior.)
    func freeze() {
        if let img = camera.latestImage {
            frozen = img
            frozenSize = camera.imageSize
            return
        }
        freezeSink = camera.$latestImage
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] img in
                guard let self else { return }
                self.frozen = img
                self.frozenSize = self.camera.imageSize
                self.freezeSink = nil
            }
    }

    // MARK: - Tap test

    /// Maps a tap in view space to a normalized image point and stores it on
    /// `flow.tapPoint`. Only meaningful once `flow.courtModel != nil`.
    func tapTest(viewPoint: CGPoint, viewSize: CGSize) {
        let mapper = AspectFillMapper(viewSize: viewSize, contentSize: frozenSize)
        let n = mapper.imageNormalized(fromView: viewPoint)
        flow.tapPoint = n
    }

    /// Returns a formatted result string and in-bounds flag for the last
    /// tap-test point, or `nil` if no court model / tap point is available.
    func tapTestResult() -> (coords: String, inBounds: Bool)? {
        guard let model = flow.courtModel, let tapPoint = flow.tapPoint else { return nil }
        let court = model.courtPoint(forImage: tapPoint)
        let inBounds = model.isInBounds(courtPoint: court)
        let coords = String(format: "x %.1f · y %.1f ft", court.x, court.y)
        return (coords, inBounds)
    }

    // MARK: - Save

    /// Persists the current calibration. Trims the venue name, falls back to
    /// "My Court", and persists `customDimensions` so custom courts round-trip.
    /// Returns `true` on success; sets `saveError` and returns `false` on failure.
    @discardableResult
    func save() -> Bool {
        let trimmed = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = StoredCalibration(
            venueName: trimmed.isEmpty ? "My Court" : trimmed,
            layout: flow.layout,
            imageCorners: flow.corners.map { CodablePoint($0) },
            customDimensions: flow.customDimensions,   // fix: old screen passed nil
            savedAt: Date()
        )
        do {
            try store.save(cal)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    // MARK: - Alert binding

    var saveErrorBinding: Binding<Bool> {
        Binding(get: { self.saveError != nil }, set: { if !$0 { self.saveError = nil } })
    }
}

// MARK: - CalibrationWizardView

/// Landscape wizard host: frozen-image canvas (left, flexible) + 204pt control
/// rail (right, fixed). Switches rail content on `model.flow.step`.
///
/// Step subviews are stubs here (Tasks 4–7 replace them). The canvas, model
/// wiring, orientation lock, and sheets are all live.
struct CalibrationWizardView: View {
    @ObservedObject var model: CalibrationModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                canvasArea
                railArea
            }
        }
        .background(PVColor.panel.ignoresSafeArea())
        .lockOrientation(.landscape)
        .onAppear {
            model.camera.start()
            model.freeze()
        }
        .alert("Couldn't save calibration", isPresented: model.saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.saveError ?? "Please try again.")
                .font(PVFont.body)
        }
        .sheet(isPresented: $model.showCustomDims) {
            CustomDimensionsSheet(
                customDimensions: $model.flow.customDimensions,
                layout: $model.flow.layout,
                onApply: { model.showCustomDims = false }
            )
        }
        .sheet(isPresented: $model.showUltraWide) {
            UltraWideFallbackCard(
                onSwitch: { model.showUltraWide = false },
                onKeep: { model.showUltraWide = false }
            )
        }
    }

    // MARK: - Canvas (left)

    private var canvasArea: some View {
        ZStack {
            if let img = model.frozen {
                // Fine-tune step: full drag-handle CalibrationView; others: static frozen image
                if model.flow.step == .fineTune {
                    CalibrationView(image: img, imageSize: model.frozenSize,
                                    corners: $model.flow.corners)
                } else {
                    Image(decorative: img, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                }

                // Court overlay for fineTune + verify (when visible)
                if (model.flow.step == .fineTune || model.flow.step == .verify),
                   model.flow.overlayVisible,
                   let courtModel = model.flow.courtModel {
                    CourtOverlayView(model: courtModel, imageSize: model.frozenSize)
                }

                // Auto-detect canvas overlays (scan band / found outline / pill)
                if model.flow.step == .detect {
                    AutoDetectCanvasOverlay(model: model)
                }

                // Tap-test canvas overlay (verify step only)
                if model.flow.step == .verify {
                    VerifyCanvasOverlay(model: model)
                }

                // Status pill — "FROZEN FRAME" on fineTune; "TAP TO TEST THE MAP" on verify
                if model.flow.step == .fineTune {
                    VStack {
                        HStack {
                            InstrumentPill("FROZEN FRAME", tint: PVColor.optic)
                                .padding(12)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                if model.flow.step == .verify {
                    VStack {
                        HStack {
                            InstrumentPill("TAP TO TEST THE MAP", tint: PVColor.optic)
                                .padding(12)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Status pill + framing overlay — camera info + guide on position step
                if model.flow.step == .position {
                    VStack {
                        HStack {
                            InstrumentPill(
                                systemImage: "camera.fill",
                                model.camera.selectedFormatDescription + " · level",
                                tint: PVColor.onDark
                            )
                            .padding(12)
                            Spacer()
                        }
                        Spacer()
                    }
                    PositionCanvasOverlay()
                }

            } else {
                // No frozen frame yet
                DashedPlaceholder("Point at the court", tag: "CAMERA READY")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
        .layoutPriority(1)
    }

    // MARK: - Rail (right, 204pt fixed)

    private var railArea: some View {
        ZStack {
            PVColor.rail.ignoresSafeArea(edges: .all)

            // Scrollable so the rail's controls (especially the bottom buttons)
            // stay reachable when content is taller than the short landscape
            // rail. `minHeight == available height` keeps buttons bottom-pinned
            // when the content fits, and lets it scroll when it doesn't.
            GeometryReader { geo in
                ScrollView {
                    stepView
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
        }
        .frame(width: 204)
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.flow.step {
        case .position:
            PositionStepView(model: model)
        case .detect:
            AutoDetectStepView(model: model)
        case .fineTune:
            FineTuneStepView(model: model)
        case .verify:
            VerifyStepView(model: model, onSaved: { dismiss() })
        }
    }
}

// MARK: - StubStepView
// Placeholder rail content. Tasks 4–7 replace each case in CalibrationWizardView.stepView.

private struct StubStepView: View {
    let label: String
    let stepNumber: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("STEP \(stepNumber)")
                .font(PVFont.dataLabel)
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)

            Text(label)
                .font(PVFont.ui(14, weight: .semibold))
                .foregroundStyle(PVColor.onDark)
                .multilineTextAlignment(.center)

            DashedPlaceholder("Task \(stepNumber + 3) stub", tag: "PLAN 8")
        }
        .padding(16)
    }
}

// MARK: - Preview

#Preview("CalibrationWizardView — position step") {
    let camera = CameraService()
    let model = CalibrationModel(camera: camera,
                                  flow: CalibrationFlow(step: .position))
    return CalibrationWizardView(model: model)
        .frame(width: 667, height: 375)   // landscape iPhone 16
        .preferredColorScheme(.dark)
}

#Preview("CalibrationWizardView — fineTune step") {
    let camera = CameraService()
    let model = CalibrationModel(camera: camera,
                                  flow: CalibrationFlow(step: .fineTune))
    return CalibrationWizardView(model: model)
        .frame(width: 667, height: 375)
        .preferredColorScheme(.dark)
}

#Preview("CalibrationWizardView — verify step") {
    let camera = CameraService()
    let model = CalibrationModel(camera: camera,
                                  flow: CalibrationFlow(step: .verify))
    return CalibrationWizardView(model: model)
        .frame(width: 667, height: 375)
        .preferredColorScheme(.dark)
}
