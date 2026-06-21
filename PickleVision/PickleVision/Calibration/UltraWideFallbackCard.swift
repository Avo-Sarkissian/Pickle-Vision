import SwiftUI

// MARK: - UltraWideFallbackCard

/// Informational sheet shown when the court won't fit at 1× zoom.
/// Offers a "Switch to 0.5×" option and a "Keep 1×" fallback.
///
/// NOTE: In v1 the 0.5× ultra-wide path has no lens-distortion calibration
/// engine. "Switch to 0.5×" is a no-op dismiss - intent is recorded only.
/// TODO: Plan - ultra-wide lens-distortion calibration
struct UltraWideFallbackCard: View {
    var onSwitch: () -> Void   // user chose 0.5× (no engine yet - record/intent only)
    var onKeep: () -> Void     // keep 1×, dismiss

    var body: some View {
        ZStack {
            PVColor.panel.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                PVCard(style: .dark) {
                    VStack(spacing: 20) {
                        // Header label
                        Text("FIELD OF VIEW")
                            .font(PVFont.dataLabel)
                            .tracking(PVFont.labelTracking)
                            .foregroundStyle(PVColor.monoLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Title
                        Text("Court won't fit at 1×")
                            .font(PVFont.screenTitle)
                            .foregroundStyle(PVColor.onDark)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Body copy
                        Text("Switch to the 0.5× ultra-wide. It needs a one-time lens-distortion calibration - its barrel curve would otherwise warp the map.")
                            .font(PVFont.body)
                            .foregroundStyle(PVColor.onDarkDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Disclaimer note
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(PVFont.mono(11, weight: .medium))
                                .foregroundStyle(PVColor.amber)
                            Text("0.5× calibration is not available in this version.")
                                .font(PVFont.mono(11, weight: .medium))
                                .foregroundStyle(PVColor.amber)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Actions
                        VStack(spacing: 10) {
                            PrimaryButton("Switch to 0.5×") {
                                // TODO: Plan - ultra-wide lens-distortion calibration
                                onSwitch()
                            }

                            SecondaryButton("Keep 1×") {
                                onKeep()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview("UltraWideFallbackCard") {
    ZStack {
        PVColor.panel.ignoresSafeArea()
        UltraWideFallbackCard(
            onSwitch: {},
            onKeep: {}
        )
    }
    .preferredColorScheme(.dark)
}
