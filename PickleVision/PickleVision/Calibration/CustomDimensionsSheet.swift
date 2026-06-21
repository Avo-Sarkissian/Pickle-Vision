import SwiftUI
import PickleVisionCore

// MARK: - CustomDimensionsSheet

/// Sheet for entering custom court dimensions (Width / Length / Kitchen NVZ) in feet.
/// UI defaults: 18 / 40 / 7 per task scope + handoff §6. Parses to Double; rejects
/// non-positive values and falls back to the last valid value.
struct CustomDimensionsSheet: View {
    @Binding var customDimensions: CustomDimensions?
    @Binding var layout: CourtLayout
    var onApply: () -> Void

    // Local field buffers (strings for TextField)
    @State private var widthText: String = "18"
    @State private var lengthText: String = "40"
    @State private var kitchenText: String = "7"

    // Last validated values (fallback on garbage input)
    @State private var validWidth: Double = 18.0
    @State private var validLength: Double = 40.0
    @State private var validKitchen: Double = 7.0

    // Inline validation feedback (e.g. kitchen too large for the length)
    @State private var note: String?

    var body: some View {
        ZStack {
            PVColor.panel.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 6) {
                        Text("CUSTOM COURT")
                            .font(PVFont.dataLabel)
                            .tracking(PVFont.labelTracking)
                            .foregroundStyle(PVColor.monoLabel)

                        Text("Court dimensions")
                            .font(PVFont.screenTitle)
                            .foregroundStyle(PVColor.onDark)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Fields card
                    PVCard(style: .dark) {
                        VStack(spacing: 20) {
                            dimensionField(
                                label: "WIDTH",
                                unit: "ft",
                                text: $widthText,
                                onCommit: {
                                    if let v = Double(widthText), v > 0 { validWidth = v }
                                    else { widthText = formatted(validWidth) }
                                }
                            )

                            divider

                            dimensionField(
                                label: "LENGTH",
                                unit: "ft",
                                text: $lengthText,
                                onCommit: {
                                    if let v = Double(lengthText), v > 0 { validLength = v }
                                    else { lengthText = formatted(validLength) }
                                }
                            )

                            divider

                            dimensionField(
                                label: "KITCHEN (NVZ)",
                                unit: "ft",
                                text: $kitchenText,
                                onCommit: {
                                    if let v = Double(kitchenText), v > 0 { validKitchen = v }
                                    else { kitchenText = formatted(validKitchen) }
                                }
                            )
                        }
                    }

                    // Inline validation note
                    if let note {
                        Text(note)
                            .font(PVFont.mono(11, weight: .regular))
                            .foregroundStyle(PVColor.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Apply button
                    PrimaryButton("Apply dimensions") {
                        applyDimensions()
                    }
                }
                .padding(24)
            }
        }
        .onAppear {
            // Seed from existing custom dimensions if available
            if let existing = customDimensions {
                validWidth = existing.widthFeet
                validLength = existing.lengthFeet
                validKitchen = existing.nonVolleyZoneFeet
                widthText = formatted(existing.widthFeet)
                lengthText = formatted(existing.lengthFeet)
                kitchenText = formatted(existing.nonVolleyZoneFeet)
            }
        }
    }

    // MARK: - Field builder

    @ViewBuilder
    private func dimensionField(
        label: String,
        unit: String,
        text: Binding<String>,
        onCommit: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(PVFont.dataLabel)
                .tracking(PVFont.labelTracking)
                .foregroundStyle(PVColor.monoLabel)

            Spacer()

            HStack(spacing: 6) {
                TextField("0", text: text, onCommit: onCommit)
                    .font(PVFont.ui(17, weight: .semibold))
                    .foregroundStyle(PVColor.onDark)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .tint(PVColor.optic)

                Text(unit)
                    .font(PVFont.mono(12, weight: .medium))
                    .foregroundStyle(PVColor.monoLabel)
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(PVColor.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Apply

    private func applyDimensions() {
        // Validate all fields before applying; fall back to last valid on garbage
        let w = Double(widthText).flatMap { $0 > 0 ? $0 : nil } ?? validWidth
        let l = Double(lengthText).flatMap { $0 > 0 ? $0 : nil } ?? validLength
        var k = Double(kitchenText).flatMap { $0 > 0 ? $0 : nil } ?? validKitchen

        // The kitchen must fit inside one half of the court, otherwise the NVZ
        // lines fall outside the court rectangle. Clamp and tell the user rather
        // than producing (and saving) a self-inconsistent court.
        let maxKitchen = l / 2
        if k >= maxKitchen {
            k = max(0.5, maxKitchen - 0.5)
            validWidth = w; validLength = l; validKitchen = k
            kitchenText = formatted(k)
            note = "Kitchen must be under half the length (\(formatted(maxKitchen)) ft). Adjusted to \(formatted(k)) ft - tap Apply to confirm."
            return   // stay open so the adjustment is visible
        }

        note = nil
        validWidth = w; validLength = l; validKitchen = k
        customDimensions = CustomDimensions(widthFeet: w, lengthFeet: l, nonVolleyZoneFeet: k)
        layout = .custom
        onApply()
    }

    // MARK: - Helpers

    private func formatted(_ value: Double) -> String {
        // Show integer if whole number, otherwise 1 decimal place
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Preview

#Preview("CustomDimensionsSheet") {
    ZStack {
        PVColor.panel.ignoresSafeArea()
        CustomDimensionsSheet(
            customDimensions: .constant(nil),
            layout: .constant(.custom),
            onApply: {}
        )
    }
    .preferredColorScheme(.dark)
}
