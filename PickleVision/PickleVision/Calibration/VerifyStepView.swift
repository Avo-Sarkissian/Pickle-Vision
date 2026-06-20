import SwiftUI
import PickleVisionCore

// MARK: - VerifyStepView

/// Step 4 — SAVE COURT.
/// Occupies the 204pt control rail.
///
/// Canvas overlays (tap-catcher + readout dot + "TAP TO TEST THE MAP" pill) are
/// handled by `VerifyCanvasOverlay`, rendered in `CalibrationWizardView.canvasArea`
/// when `step == .verify`.
///
/// Rail contents:
///  • "Save court" title + "STORED ON DEVICE" sublabel
///  • VENUE NAME label + TextField
///  • FIT QUALITY PVCard — qualitative label + 4-segment bar + corners count + note
///  • Back / Save court buttons
struct VerifyStepView: View {
    @ObservedObject var model: CalibrationModel
    var onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            Text("Save court")
                .font(PVFont.screenTitle)
                .foregroundStyle(PVColor.onDark)

            Text("STORED ON DEVICE")
                .font(PVFont.dataLabel)
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)
                .padding(.top, 2)
                .padding(.bottom, 14)

            // ── Venue name ──────────────────────────────────────────────────
            Text("VENUE NAME")
                .font(PVFont.dataLabel)
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)
                .padding(.bottom, 6)

            TextField("My Court", text: $model.venueName)
                .font(PVFont.ui(14, weight: .regular))
                .foregroundStyle(PVColor.onDark)
                .tint(PVColor.optic)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(PVColor.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(PVColor.cardBorder, lineWidth: 1)
                        )
                )
                .padding(.bottom, 12)

            // ── Fit quality card ─────────────────────────────────────────────
            PVCard(style: .dark) {
                VStack(alignment: .leading, spacing: 8) {

                    // Header row: "FIT QUALITY" label + qualitative value
                    HStack {
                        Text("FIT QUALITY")
                            .font(PVFont.dataLabel)
                            .tracking(PVFont.labelTracking)
                            .foregroundStyle(PVColor.monoLabel)
                        Spacer(minLength: 4)
                        Text(model.flow.fitQuality.quality.label)
                            .font(PVFont.mono(11, weight: .semibold))
                            .foregroundStyle(PVColor.inBounds)
                    }

                    // 4-segment bar
                    FitQualityBar(
                        filledSegments: FitQuality.barSegments(for: model.flow.fitQuality.residual)
                    )

                    // Corners set indicator
                    HStack(spacing: 5) {
                        Circle()
                            .fill(PVColor.optic)
                            .frame(width: 6, height: 6)
                        Text("\(model.flow.cornersSetCount) / 4 corners set")
                            .font(PVFont.mono(10, weight: .regular))
                            .foregroundStyle(PVColor.onDark)
                    }

                    // Honesty note
                    Text("From corner-fit residual. Per-zone ± inches arrive in Phase 2.")
                        .font(PVFont.mono(9, weight: .regular))
                        .foregroundStyle(PVColor.onDarkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 12)

            Spacer(minLength: 8)

            // ── Back ─────────────────────────────────────────────────────────
            SecondaryButton("Back") {
                model.flow.back()
            }
            .padding(.bottom, 8)

            // ── Save court ───────────────────────────────────────────────────
            PrimaryButton("Save court") {
                if model.save() {
                    onSaved()
                }
            }
        }
        .padding(16)
    }
}

// MARK: - FitQualityBar

/// 4 rounded-rectangle segments; `filledSegments` of them use `PVColor.inBounds`.
private struct FitQualityBar: View {
    let filledSegments: Int   // 0...4

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < filledSegments ? PVColor.inBounds : PVColor.cardBorder)
                    .frame(maxWidth: .infinity)
                    .frame(height: 6)
            }
        }
    }
}

// MARK: - VerifyCanvasOverlay

/// Tap-test canvas overlays for the `.verify` step:
///  • "TAP TO TEST THE MAP" pill (replaces "FROZEN FRAME" in this step)
///  • Tap-catcher that calls `model.tapTest(viewPoint:viewSize:)`
///  • If `model.flow.tapPoint != nil` and result is non-nil: marker dot + readout card
struct VerifyCanvasOverlay: View {
    @ObservedObject var model: CalibrationModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Tap-catcher (full canvas)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        model.tapTest(viewPoint: loc, viewSize: geo.size)
                    }

                // Marker + readout card
                if let tapNorm = model.flow.tapPoint,
                   let result  = model.tapTestResult() {

                    let mapper  = AspectFillMapper(viewSize: geo.size, contentSize: model.frozenSize)
                    let viewPt  = mapper.view(fromImageNormalized: tapNorm)
                    let dotSize: CGFloat = 10
                    let cardOffsetY: CGFloat = -36

                    // Marker dot
                    Circle()
                        .fill(result.inBounds ? PVColor.inBounds : PVColor.outBounds)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                        .position(viewPt)

                    // Readout card
                    TapReadoutCard(
                        coords: result.coords,
                        inBounds: result.inBounds
                    )
                    .position(x: viewPt.x, y: viewPt.y + cardOffsetY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - TapReadoutCard

/// Small readout card showing "x 0.2 · y 12.6 ft" + IN / OUT badge.
private struct TapReadoutCard: View {
    let coords: String
    let inBounds: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(coords)
                .font(PVFont.mono(10, weight: .regular))
                .foregroundStyle(PVColor.onDark)

            Text(inBounds ? "IN" : "OUT")
                .font(PVFont.mono(10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(inBounds ? PVColor.inBounds : PVColor.outBounds)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(PVColor.pillFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(PVColor.cardBorder.opacity(0.8), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview("VerifyStepView — rail") {
    let camera = CameraService()
    let model  = CalibrationModel(camera: camera, flow: CalibrationFlow(step: .verify))
    return ZStack {
        PVColor.rail.ignoresSafeArea()
        VerifyStepView(model: model, onSaved: {})
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}
