import SwiftUI
import PickleVisionCore

// MARK: - PositionStepView

/// Step 1 - POSITION CHECK.
/// Occupies the 204pt control rail. The canvas overlay (framing guide + corner
/// ticks + fit-the-court caption) is a separate `PositionCanvasOverlay` view
/// inserted into `CalibrationWizardView.canvasArea` for the `.position` step.
///
/// Continue is ALWAYS enabled - checks are advisory guidance only.
struct PositionStepView: View {
    @ObservedObject var model: CalibrationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            Text("POSITION CHECK")
                .font(PVFont.mono(10, weight: .semibold))
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)
                .padding(.bottom, 14)

            // ── Check rows ──────────────────────────────────────────────────
            checkRow(
                symbol: model.flow.checks.steady
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill",
                label: "Phone steady",
                passing: model.flow.checks.steady
            )
            .padding(.bottom, 10)

            checkRow(
                symbol: model.flow.checks.framed
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill",
                label: "Whole court visible",
                passing: model.flow.checks.framed
            )
            .padding(.bottom, 10)

            // Angle row - always amber (advisory "raise" hint)
            checkRow(
                symbol: "exclamationmark.circle.fill",
                label: "Raise mount ~1 ft",
                passing: model.flow.checks.angle
            )

            // ── Angle note ──────────────────────────────────────────────────
            Text("A higher angle sharpens near-line calls - but any angle still works.")
                .font(PVFont.mono(9, weight: .regular))
                .foregroundStyle(PVColor.onDarkDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 18)

            // ── Primary CTA - ALWAYS enabled, never .disabled ────────────────
            PrimaryButton("Continue anyway") {
                model.flow.continueFromPosition()
            }
            .padding(.bottom, 10)

            // ── Secondary CTA ───────────────────────────────────────────────
            SecondaryButton("Calibrate manually") {
                model.flow.calibrateManually()
            }

            // ── Progress caption ─────────────────────────────────────────────
            Text("\(model.flow.checks.passingCount) / \(model.flow.checks.total) - go anyway")
                .font(PVFont.mono(9, weight: .medium))
                .foregroundStyle(PVColor.onDarkDim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            Spacer(minLength: 12)

            // ── Ultra-wide fallback link ─────────────────────────────────────
            Button {
                model.showUltraWide = true
            } label: {
                Text("Won't fit? Use 0.5× →")
                    .font(PVFont.mono(9, weight: .medium))
                    .foregroundStyle(PVColor.onDarkDim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .onAppear {
            // Default checks to match screenshot 2/3 state (steady ✓, framed ✓, angle ✗).
            // Sensing is not wired in this plan; values are advisory only.
            model.flow.checks = SetupChecks(steady: true, framed: true, angle: false)
        }
    }

    // MARK: - Check row helper

    @ViewBuilder
    private func checkRow(symbol: String, label: String, passing: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(PVFont.mono(13, weight: .semibold))
                .foregroundStyle(passing ? PVColor.optic : PVColor.amber)
            Text(label)
                .font(PVFont.ui(13, weight: .regular))
                .foregroundStyle(PVColor.onDark)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - PositionCanvasOverlay

/// Dashed framing guide + yellow corner ticks + "Fit the whole court" caption.
/// Rendered in `CalibrationWizardView.canvasArea` when `step == .position`.
struct PositionCanvasOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let insetX = geo.size.width  * 0.12
            let insetY = geo.size.height * 0.12
            let rect   = CGRect(
                x: insetX,
                y: insetY,
                width:  geo.size.width  - 2 * insetX,
                height: geo.size.height - 2 * insetY
            )
            ZStack {
                // Dashed framing rectangle
                Rectangle()
                    .path(in: rect)
                    .stroke(
                        PVColor.optic.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )

                // Corner ticks (four L-shapes)
                cornerTicks(rect: rect)

                // Caption
                Text("Fit the whole court in the frame")
                    .font(PVFont.body)
                    .foregroundStyle(PVColor.onDark.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .position(x: geo.size.width / 2, y: rect.maxY + 18)
            }
        }
    }

    @ViewBuilder
    private func cornerTicks(rect: CGRect) -> some View {
        let arm: CGFloat = 18  // length of each tick arm
        let w: CGFloat   = 2   // stroke width

        Canvas { ctx, _ in
            let corners: [(CGPoint, Int)] = [
                (CGPoint(x: rect.minX, y: rect.minY), 0),   // NL
                (CGPoint(x: rect.maxX, y: rect.minY), 1),   // NR
                (CGPoint(x: rect.maxX, y: rect.maxY), 2),   // FR
                (CGPoint(x: rect.minX, y: rect.maxY), 3),   // FL
            ]

            var path = Path()
            for (pt, idx) in corners {
                let hSign: CGFloat = (idx == 1 || idx == 2) ? -1 : 1
                let vSign: CGFloat = (idx == 2 || idx == 3) ? -1 : 1
                // Horizontal arm
                path.move(to: pt)
                path.addLine(to: CGPoint(x: pt.x + hSign * arm, y: pt.y))
                // Vertical arm
                path.move(to: pt)
                path.addLine(to: CGPoint(x: pt.x, y: pt.y + vSign * arm))
            }
            ctx.stroke(path, with: .color(PVColor.optic), lineWidth: w)
        }
    }
}

// MARK: - Preview

#Preview("PositionStepView - rail") {
    let camera = CameraService()
    let model  = CalibrationModel(camera: camera, flow: CalibrationFlow(step: .position))
    return ZStack {
        PVColor.rail.ignoresSafeArea()
        PositionStepView(model: model)
            .frame(width: 204)
    }
    .preferredColorScheme(.dark)
}

#Preview("PositionCanvasOverlay") {
    ZStack {
        PVColor.panel.ignoresSafeArea()
        PositionCanvasOverlay()
    }
    .frame(width: 463, height: 375)
    .preferredColorScheme(.dark)
}
