import SwiftUI

// MARK: - DriftGuardOverlay

/// Camera-screen overlay shown when the mount has shifted and calls are paused.
///
/// This is a **UI component only** — it accepts callbacks and renders the
/// "CALLS PAUSED" + re-aligning modal state. It does NOT sense drift or wire to
/// `DriftDetector`/`StabilityCheck`; that runtime wiring is intentionally deferred
/// to the Plan 4 engine. Wire `onReTap` / `onDismiss` at the call-site once the
/// engine is ready.
///
/// The ghost-court trapezoid behind the modal is decorative/static (no real
/// `CourtModel`) — it represents a drifted court position for visual context.
///
/// Framed for landscape (tripod-mounted iPhone, full-bleed camera feed beneath).
struct DriftGuardOverlay: View {
    /// Called when the user taps "Re-tap court" — caller should navigate to
    /// manual calibration step 3 (fine-tune).
    let onReTap: () -> Void
    /// Called when the user taps "Dismiss" — caller should hide this overlay
    /// and resume whatever partial state is appropriate.
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // 1. Dark scrim over the live feed
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            // 2. Ghost drifted-court trapezoid (decorative, static, amber dashed)
            GhostCourtTrapezoid()

            // 3. Modal card — centered
            modalCard
        }
        // CALLS PAUSED pill — top-left, over everything
        .overlay(alignment: .topLeading) {
            callsPausedPill
                .padding(.top, 16)
                .padding(.leading, 20)
        }
    }

    // MARK: - Sub-views

    private var callsPausedPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(PVColor.amber)
                .frame(width: 7, height: 7)
            Text("CALLS\nPAUSED")
                .font(PVFont.mono(10, weight: .semibold))
                .tracking(PVFont.labelTracking)
                .lineSpacing(1)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(PVColor.amber)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(PVColor.pillFill)
                .overlay(Capsule().strokeBorder(PVColor.amber.opacity(0.45), lineWidth: 1))
        )
    }

    private var modalCard: some View {
        VStack(spacing: 0) {
            // Amber spinner / progress ring
            ProgressView()
                .progressViewStyle(.circular)
                .tint(PVColor.amber)
                .scaleEffect(1.4)
                .padding(.bottom, 18)

            // Title
            Text("Mount moved — re-aligning")
                .font(PVFont.screenTitle)
                .tracking(PVFont.displayTracking)
                .foregroundStyle(PVColor.onDark)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            // Body copy
            Text("The court no longer lines up with the saved map. Pausing calls so a stale map can't make a bad one.")
                .font(PVFont.bodySmall)
                .foregroundStyle(PVColor.onDarkDim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
                .padding(.bottom, 22)

            // Buttons
            HStack(spacing: 10) {
                // Re-tap court — amber prominent (primary action for this warning state)
                Button(action: onReTap) {
                    Text("Re-tap court")
                        .font(PVFont.ui(15, weight: .semibold))
                        .foregroundStyle(PVColor.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 13).fill(PVColor.amber))
                }
                .buttonStyle(.plain)

                // Dismiss — secondary
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(PVFont.ui(15, weight: .medium))
                        .foregroundStyle(PVColor.onDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(PVColor.rail)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13)
                                        .strokeBorder(PVColor.cardBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(PVColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(PVColor.cardBorder, lineWidth: 1)
                )
        )
        .frame(maxWidth: 360)
        .padding(.horizontal, 40)
    }
}

// MARK: - GhostCourtTrapezoid

/// A static amber dashed trapezoid representing a drifted court position.
/// Purely decorative — conveys visually that the saved court map no longer
/// aligns with the live feed. Uses vector `Path` (no raster, no CourtModel).
private struct GhostCourtTrapezoid: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Perspective trapezoid: wider near-end at bottom, narrower far-end at top.
            // Shifted right and slightly low to suggest the court drifted.
            let offsetX: CGFloat = w * 0.08
            let offsetY: CGFloat = h * 0.06

            let nearLeft   = CGPoint(x: w * 0.28 + offsetX, y: h * 0.82 + offsetY)
            let nearRight  = CGPoint(x: w * 0.78 + offsetX, y: h * 0.88 + offsetY)
            let farRight   = CGPoint(x: w * 0.68 + offsetX, y: h * 0.45 + offsetY)
            let farLeft    = CGPoint(x: w * 0.32 + offsetX, y: h * 0.40 + offsetY)

            Path { path in
                path.move(to: nearLeft)
                path.addLine(to: nearRight)
                path.addLine(to: farRight)
                path.addLine(to: farLeft)
                path.closeSubpath()
            }
            .stroke(
                PVColor.amber.opacity(0.28),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("DriftGuardOverlay — landscape", traits: .landscapeLeft) {
    ZStack {
        // Stand-in for the live camera feed
        PVColor.feedGradient
            .ignoresSafeArea()

        DriftGuardOverlay(
            onReTap:   { print("Re-tap court tapped") },
            onDismiss: { print("Dismiss tapped") }
        )
    }
    // NOTE: This component is intentionally unreachable from the running app until
    // the Plan 4 DriftDetector engine wires it at runtime. The #Preview is the
    // primary verification surface during development.
}
