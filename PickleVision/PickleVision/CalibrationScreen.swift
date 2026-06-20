import SwiftUI
import Combine
import PickleVisionCore

/// Thin host that builds the right `CalibrationModel` and renders
/// `CalibrationWizardView`. Two entry points:
///   • Camera-launched (standard):  `init(camera:)` — starts the wizard at Step 1 (Position).
///   • Express re-calibrate:         `init(camera:, reCalibrate:)` — jumps to Step 3 (Fine-tune)
///     with the saved court's corners, layout, custom dimensions, and venue preloaded.
///   • Convenience `init(reloading:)` — HomeView path; creates a fresh CameraService.
struct CalibrationScreen: View {
    @ObservedObject var camera: CameraService
    @StateObject private var model: CalibrationModel

    // MARK: - Inits

    /// Camera-launched path: caller owns the `CameraService`. Wizard starts at
    /// Step 1 (Position) with a default `CalibrationFlow`.
    init(camera: CameraService) {
        _camera = ObservedObject(wrappedValue: camera)
        _model = StateObject(wrappedValue: CalibrationModel(camera: camera))
    }

    /// Express re-calibrate (generic): caller supplies both camera and optional
    /// stored court. If `reCalibrate` is non-nil, lands on Step 3 (Fine-tune)
    /// with corners/layout/dims/venue preloaded. If nil, behaves like the
    /// standard camera-launched path.
    init(camera: CameraService, reCalibrate: StoredCalibration?) {
        _camera = ObservedObject(wrappedValue: camera)
        if let stored = reCalibrate {
            let flow = CalibrationFlow.forExpressReCal(
                corners: stored.imageCorners.map { $0.cgPoint },
                layout: stored.layout,
                customDimensions: stored.customDimensions
            )
            _model = StateObject(wrappedValue: CalibrationModel(
                camera: camera,
                flow: flow,
                venueName: stored.venueName
            ))
        } else {
            _model = StateObject(wrappedValue: CalibrationModel(camera: camera))
        }
    }

    /// HomeView convenience: express re-calibrate with a freshly created
    /// CameraService. Lands on Step 3 (Fine-tune) with the saved court preloaded.
    init(reloading calibration: StoredCalibration) {
        let cam = CameraService()
        _camera = ObservedObject(wrappedValue: cam)
        let flow = CalibrationFlow.forExpressReCal(
            corners: calibration.imageCorners.map { $0.cgPoint },
            layout: calibration.layout,
            customDimensions: calibration.customDimensions
        )
        _model = StateObject(wrappedValue: CalibrationModel(
            camera: cam,
            flow: flow,
            venueName: calibration.venueName
        ))
    }

    // MARK: - Body

    var body: some View {
        CalibrationWizardView(model: model)
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
    }
}
