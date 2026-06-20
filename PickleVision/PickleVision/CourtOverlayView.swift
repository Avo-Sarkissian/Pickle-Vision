import SwiftUI
import PickleVisionCore

/// Calibration-overlay compatibility wrapper.
/// Delegates to the reusable zone-colored `CourtOverlay` (DesignSystem/CourtOverlay.swift).
/// Kept so the existing CalibrationScreen call-site `CourtOverlayView(model:imageSize:)` compiles unchanged.
struct CourtOverlayView: View {
    let model: CourtModel
    let imageSize: CGSize

    var body: some View {
        CourtOverlay(model: model, imageSize: imageSize)
    }
}
