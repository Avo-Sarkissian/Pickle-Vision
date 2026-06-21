import SwiftUI

/// Semantic color tokens for "Instrument · Daylight".
/// Exact hex values from docs/design/handoff-instrument-daylight.md §Design Tokens.
enum PVColor {
    /// 24-bit RGB hex → Color (e.g. 0xe6f53a). `opacity` applies an alpha tint.
    static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: opacity
        )
    }

    // Light · menus
    static let paper = hex(0xf4f5f3)        // light bg
    static let ink = hex(0x14181b)          // primary text / text on yellow
    static let hairline = hex(0xe8ebe9)     // card hairline
    static let mutedLight = hex(0x5e6a70)   // secondary text on light

    // Semantic
    static let inBounds = hex(0x4d9bff)     // IN call / in-bounds blue
    static let inSwatch = hex(0x2f63c2)     // blue swatch
    static let outBounds = hex(0x46c46a)    // OUT call / apron green
    static let optic = hex(0xe6f53a)        // computed/active accent (optic yellow)
    static let amber = hex(0xf4b53a)        // caution (thermal / drift / NVZ)
    static let recordRed = hex(0xe5402a)    // REC dot / destructive

    // Dark · video overlay
    static let panel = hex(0x0c1216)        // instrument panel
    static let rail = hex(0x101920)         // control rail bg
    static let cardBorder = hex(0x25333a)   // dark panel border
    static let pillFill = Color(red: 8/255, green: 14/255, blue: 17/255, opacity: 0.82) // rgba(8,14,17,0.82)
    static let onDark = hex(0xeaf6f9)       // near-white text on dark
    static let onDarkDim = hex(0x9fb4bd)    // dim text on dark
    static let monoLabel = hex(0x5f8595)    // mono labels on dark

    // Court zone fills (low-alpha - rgba(61,134,245,0.06–0.16))
    static let inBoundsFill = Color(red: 61/255, green: 134/255, blue: 245/255, opacity: 0.14)
    static let outBoundsFill = Color(red: 70/255, green: 196/255, blue: 106/255, opacity: 0.10)

    /// Live-video stand-in: linear-gradient(176deg,#13343a,#0e2228,#0a1418).
    /// 176° CSS ≈ near-vertical top→bottom; map to SwiftUI top→bottom points.
    static let feedGradient = LinearGradient(
        gradient: Gradient(colors: [hex(0x13343a), hex(0x0e2228), hex(0x0a1418)]),
        startPoint: .top,
        endPoint: .bottom
    )
}

#Preview("PVColor swatches") {
    ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            swatch("paper", PVColor.paper)
            swatch("ink", PVColor.ink)
            swatch("inBounds", PVColor.inBounds)
            swatch("inSwatch", PVColor.inSwatch)
            swatch("outBounds", PVColor.outBounds)
            swatch("optic", PVColor.optic)
            swatch("amber", PVColor.amber)
            swatch("recordRed", PVColor.recordRed)
            swatch("panel", PVColor.panel)
            swatch("rail", PVColor.rail)
            swatch("hairline", PVColor.hairline)
            swatch("onDark", PVColor.onDark)
            swatch("onDarkDim", PVColor.onDarkDim)
            swatch("mutedLight", PVColor.mutedLight)
            swatch("inBoundsFill", PVColor.inBoundsFill)
            swatch("outBoundsFill", PVColor.outBoundsFill)
            RoundedRectangle(cornerRadius: 8)
                .fill(PVColor.feedGradient)
                .frame(height: 60)
                .overlay(Text("feedGradient").foregroundStyle(PVColor.onDark).font(.caption))
        }
        .padding()
    }
}

@ViewBuilder private func swatch(_ name: String, _ color: Color) -> some View {
    HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 56, height: 28)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.3)))
        Text(name).font(.system(.caption, design: .monospaced))
    }
}

// MARK: - PVFont

/// Type roles for "Instrument · Daylight".
/// SF Pro Display/Text (system, .default design) + SF Mono (.monospaced design).
/// Sizes from docs/design/handoff-instrument-daylight.md §Typography.
enum PVFont {
    /// SF Pro Display - titles / hero / scoreboard (bold-heavy, tight tracking).
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    /// SF Pro Text - UI / body.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    /// SF Mono - data readouts / labels.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Named roles (handoff size scale: hero 44 / H2 28 / screen-title 20–28 / body 13–14 / data-label 9–11)
    static let hero = display(44, weight: .heavy)
    static let h2 = display(28, weight: .bold)
    static let screenTitle = display(22, weight: .bold)
    static let body = ui(14, weight: .regular)
    static let bodySmall = ui(13, weight: .regular)
    static let dataLabel = mono(10, weight: .medium)
    static let dataValue = mono(13, weight: .regular)

    /// Tracking for display titles (handoff: -0.01em → ~-0.5pt at hero size).
    static let displayTracking: CGFloat = -0.5
    /// Letter-spacing for uppercase mono labels (handoff: 0.1–0.18em → ~1.4pt at 10pt).
    static let labelTracking: CGFloat = 1.4
}

#Preview("PVFont specimen") {
    VStack(alignment: .leading, spacing: 14) {
        Text("Ready to ref.").font(PVFont.hero).tracking(PVFont.displayTracking)
        Text("Section H2").font(PVFont.h2).tracking(PVFont.displayTracking)
        Text("Screen title").font(PVFont.screenTitle)
        Text("Body 14 - the quick brown fox").font(PVFont.body)
        Text("Body small 13").font(PVFont.bodySmall)
        Text("CAPTURE PROFILE")
            .font(PVFont.dataLabel).tracking(PVFont.labelTracking)
            .foregroundStyle(PVColor.mutedLight)
        Text("1080p · 120fps").font(PVFont.dataValue)
    }
    .padding()
}
