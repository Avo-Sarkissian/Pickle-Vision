import SwiftUI
import PickleVisionCore

// MARK: - FineTuneStepView

/// Step 3 - CALIBRATE / DRAG TO THE LINES.
/// Occupies the 204pt control rail. The canvas (drag handles + loupe) is
/// `CalibrationView` rendered by `CalibrationWizardView.canvasArea`.
///
/// Rail contents:
///  • "Calibrate" title + "DRAG TO THE LINES" sublabel
///  • LAYOUT section - SegmentedChips: Pickleball / Tennis box / Custom
///  • Court overlay toggle
///  • "N / 4 corners set" indicator
///  • Re-freeze + Save buttons
struct FineTuneStepView: View {
    @ObservedObject var model: CalibrationModel

    // MARK: - Layout chip IDs
    private let chipPickleball = "regulationPickleball"
    private let chipTennis     = "tennisFrontBox"
    private let chipCustom     = "custom"

    private var layoutChips: [SegmentedChip] {
        [
            SegmentedChip(id: chipPickleball, title: "Pickleball",  trailing: "20×44"),
            SegmentedChip(id: chipTennis,     title: "Tennis box",  trailing: "27×42"),
            SegmentedChip(id: chipCustom,     title: "Custom",      trailing: "set ft"),
        ]
    }

    /// Bridge between `CourtLayout` and the `SegmentedChips` string-ID selection.
    private var layoutSelection: Binding<SegmentedChip.ID> {
        Binding(
            get: { model.flow.layout.rawValue },
            set: { newID in
                if newID == chipCustom {
                    // Tap Custom → apply layout + open dims sheet
                    model.flow.layout = .custom
                    model.showCustomDims = true
                } else {
                    model.flow.layout = CourtLayout(rawValue: newID) ?? model.flow.layout
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            Text("Calibrate")
                .font(PVFont.screenTitle)
                .foregroundStyle(PVColor.onDark)

            Text("DRAG TO THE LINES")
                .font(PVFont.dataLabel)
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)
                .padding(.top, 2)
                .padding(.bottom, 14)

            // ── LAYOUT section ───────────────────────────────────────────────
            Text("LAYOUT")
                .font(PVFont.dataLabel)
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)
                .padding(.bottom, 6)

            SegmentedChips(layoutChips, selection: layoutSelection)
                .padding(.bottom, 14)

            // ── Court overlay toggle ─────────────────────────────────────────
            HStack {
                Text("Court overlay")
                    .font(PVFont.ui(13, weight: .regular))
                    .foregroundStyle(PVColor.onDark)
                Spacer(minLength: 8)
                Toggle("", isOn: $model.flow.overlayVisible)
                    .labelsHidden()
                    .tint(PVColor.optic)
                    .scaleEffect(0.8)
            }
            .padding(.bottom, 14)

            // ── Corners set indicator ────────────────────────────────────────
            HStack(spacing: 6) {
                Circle()
                    .fill(PVColor.optic)
                    .frame(width: 7, height: 7)
                Text("\(model.flow.cornersSetCount) / 4 corners set")
                    .font(PVFont.mono(11, weight: .regular))
                    .foregroundStyle(PVColor.onDark)
            }
            .padding(.bottom, 14)

            Spacer(minLength: 8)

            // ── Re-freeze ────────────────────────────────────────────────────
            SecondaryButton("Re-freeze") {
                model.freeze()
            }
            .padding(.bottom, 8)

            // ── Save (advance to Verify) ─────────────────────────────────────
            PrimaryButton("Save") {
                model.flow.advance()
            }
        }
        .padding(16)
    }
}

// MARK: - Preview

#Preview("FineTuneStepView - rail") {
    let camera = CameraService()
    let model  = CalibrationModel(camera: camera, flow: CalibrationFlow(step: .fineTune))
    return ZStack {
        PVColor.rail.ignoresSafeArea()
        FineTuneStepView(model: model)
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}
