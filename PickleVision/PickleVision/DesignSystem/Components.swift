import SwiftUI

// MARK: - InstrumentPill

/// Dark status pill - chrome on the camera/calibration screens.
/// Fill rgba(8,14,17,0.82), hairline border, mono text.
struct InstrumentPill: View {
    let systemImage: String?
    let text: String
    let tint: Color

    init(systemImage: String? = nil, _ text: String, tint: Color = PVColor.onDark) {
        self.systemImage = systemImage
        self.text = text
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(PVFont.mono(10, weight: .semibold)) }
            Text(text).font(PVFont.mono(11, weight: .medium)).tracking(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(PVColor.pillFill)
                .overlay(Capsule().strokeBorder(PVColor.cardBorder.opacity(0.8), lineWidth: 1))
        )
    }
}

// MARK: - StatusReadout

/// Mono two-line readout (e.g. "REC" over "12:04") with an optional leading dot.
struct StatusReadout: View {
    let label: String
    let value: String
    let dotColor: Color?

    init(label: String, value: String, dotColor: Color? = nil) {
        self.label = label
        self.value = value
        self.dotColor = dotColor
    }

    var body: some View {
        HStack(spacing: 8) {
            if let dotColor { Circle().fill(dotColor).frame(width: 7, height: 7) }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(PVFont.mono(10, weight: .semibold)).tracking(0.8)
                Text(value).font(PVFont.mono(11, weight: .regular))
            }
        }
        .foregroundStyle(PVColor.onDark)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9).fill(PVColor.pillFill)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(PVColor.cardBorder.opacity(0.8), lineWidth: 1))
        )
    }
}

// MARK: - PrimaryButton

/// Optic-yellow primary action with ink text (Home "Start a session →", "Save court").
struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(PVFont.ui(16, weight: .semibold))
            }
            .foregroundStyle(PVColor.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(PVColor.optic))
            .shadow(color: PVColor.optic.opacity(0.35), radius: 12, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SecondaryButton

/// Neutral outlined secondary action ("Calibrate manually", "Re-freeze", "Back").
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(PVFont.ui(15, weight: .medium))
                .foregroundStyle(PVColor.onDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(PVColor.rail)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PVColor.cardBorder, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SegmentedChip

/// One option in a SegmentedChips column.
struct SegmentedChip: Identifiable {
    let id: String
    let title: String
    let trailing: String?

    init(id: String, title: String, trailing: String? = nil) {
        self.id = id
        self.title = title
        self.trailing = trailing
    }
}

// MARK: - SegmentedChips

/// Single-select vertical chip column. Active = optic-yellow + ink (handoff active-chip rule).
struct SegmentedChips: View {
    let chips: [SegmentedChip]
    @Binding var selection: SegmentedChip.ID

    init(_ chips: [SegmentedChip], selection: Binding<SegmentedChip.ID>) {
        self.chips = chips
        self._selection = selection
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(chips) { chip in
                let active = chip.id == selection
                Button { selection = chip.id } label: {
                    HStack {
                        Text(chip.title)
                            .font(PVFont.ui(14, weight: active ? .semibold : .regular))
                        Spacer(minLength: 8)
                        if let trailing = chip.trailing {
                            Text(trailing)
                                .font(PVFont.mono(10, weight: .medium))
                                .opacity(active ? 0.7 : 0.6)
                        }
                    }
                    .foregroundStyle(active ? PVColor.ink : PVColor.onDarkDim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(active ? PVColor.optic : PVColor.rail)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(active ? Color.clear : PVColor.cardBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - PVCard

/// Styled surface container. .light = white card on paper; .dark = instrument panel.
struct PVCard<Content: View>: View {
    enum Style { case light, dark }
    let style: Style
    let content: Content

    init(style: Style = .light, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(style == .light ? Color.white : PVColor.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style == .light ? PVColor.hairline : PVColor.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: style == .light ? Color.black.opacity(0.08) : .clear, radius: 3, y: 1)
            )
    }
}

// MARK: - DashedPlaceholder

/// Dashed, ghosted placeholder for not-yet-shipped affordances (Phase-2/6 tags, empty states).
struct DashedPlaceholder: View {
    let text: String
    let tag: String?

    init(_ text: String, tag: String? = nil) {
        self.text = text
        self.tag = tag
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(PVFont.mono(11, weight: .medium)).tracking(0.6)
                .multilineTextAlignment(.center)
            if let tag {
                Text(tag)
                    .font(PVFont.mono(9, weight: .semibold)).tracking(1.2)
                    .opacity(0.7)
            }
        }
        .foregroundStyle(PVColor.onDarkDim)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    PVColor.onDarkDim.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
    }
}

// MARK: - Preview

#Preview("Atom gallery") {
    ZStack {
        PVColor.feedGradient.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    StatusReadout(label: "REC", value: "12:04", dotColor: PVColor.recordRed)
                    InstrumentPill("1080p · 120fps")
                    InstrumentPill("118 fps")
                    InstrumentPill(systemImage: "thermometer.medium", "COOLING · 90fps", tint: PVColor.amber)
                }
                PrimaryButton("Save court", systemImage: "checkmark") {}
                SecondaryButton("Calibrate manually") {}
                SegmentedChips(
                    [SegmentedChip(id: "pb", title: "Pickleball", trailing: "20×44"),
                     SegmentedChip(id: "tn", title: "Tennis box", trailing: "27×42"),
                     SegmentedChip(id: "cu", title: "Custom", trailing: "set ft")],
                    selection: .constant("pb")
                )
                DashedPlaceholder("IN / OUT CALLS", tag: "PHASE 2")
                PVCard(style: .light) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Riverside · Court 3").font(PVFont.ui(15, weight: .semibold)).foregroundStyle(PVColor.ink)
                        Text("Pickleball · 20×44 ft · 2d ago").font(PVFont.bodySmall).foregroundStyle(PVColor.mutedLight)
                    }
                }
                PVCard(style: .dark) {
                    Text("FROZEN FRAME").font(PVFont.dataLabel).tracking(PVFont.labelTracking).foregroundStyle(PVColor.optic)
                }
            }
            .padding()
        }
    }
}
