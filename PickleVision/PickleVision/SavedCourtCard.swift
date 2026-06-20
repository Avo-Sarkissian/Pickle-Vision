import SwiftUI
import PickleVisionCore

/// One saved-court row on Home: mini court thumbnail + venue + a single
/// metadata line (layout · dimensions · relative save date) + a reload (↻)
/// affordance. Shows ONLY persisted fields (honesty rule).
struct SavedCourtCard: View {
    let calibration: StoredCalibration
    var onStart: () -> Void
    let onReload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CourtThumbnail(calibration: calibration)
                .frame(width: 56, height: 44)

            Button(action: onStart) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(calibration.venueName)
                        .font(PVFont.ui(15, weight: .semibold))
                        .foregroundStyle(PVColor.ink)
                        .lineLimit(1)
                    Text(metadataLine)
                        .font(PVFont.ui(12))
                        .foregroundStyle(PVColor.mutedLight)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start session at \(calibration.venueName)")

            Spacer(minLength: 8)

            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
                    .font(PVFont.ui(16, weight: .semibold))
                    .foregroundStyle(PVColor.ink)
                    .frame(width: 44, height: 44)        // ≥44pt hit target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Re-calibrate \(calibration.venueName)")
        }
        .padding(12)
        .background(PVColor.paper, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PVColor.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    // "Pickleball · 20×44 ft · 2d ago"
    private var metadataLine: String {
        "\(layoutName) · \(dimensionsText) · \(relativeDate)"
    }

    private var layoutName: String {
        switch calibration.layout {
        case .regulationPickleball: return "Pickleball"
        case .tennisFrontBox:       return "Tennis box"
        case .custom:               return "Custom"
        }
    }

    private var dimensionsText: String {
        let profile = CourtProfile.make(layout: calibration.layout,
                                        custom: calibration.customDimensions)
        return "\(trim(profile.widthFeet))×\(trim(profile.lengthFeet)) ft"
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: calibration.savedAt, relativeTo: Date())
    }
}

// MARK: - CourtThumbnail

/// Dark mini-tile rendering the saved court's outline via the Plan 5 CourtOverlay.
private struct CourtThumbnail: View {
    let calibration: StoredCalibration
    private let model: CourtModel?
    private let contentSize: CGSize

    init(calibration: StoredCalibration) {
        self.calibration = calibration
        // Build the homography once per card, not on every body re-render.
        self.model = CalibrationStore.courtModel(from: calibration)
        self.contentSize = Self.imageSize(for: calibration)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(PVColor.panel)
            if let model {
                CourtOverlay(model: model,
                             imageSize: contentSize,
                             lineWidth: 1.2,
                             opacity: 1.0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Stored corners are normalized [0,1]; the bounding box (floored at 1) keeps
    // the overlay's AspectFillMapper in normalized space.
    private static func imageSize(for cal: StoredCalibration) -> CGSize {
        let xs = cal.imageCorners.map(\.x)
        let ys = cal.imageCorners.map(\.y)
        let w = max((xs.max() ?? 1) - (xs.min() ?? 0), 1)
        let h = max((ys.max() ?? 1) - (ys.min() ?? 0), 1)
        return CGSize(width: w, height: h)
    }
}

// MARK: - Preview

#Preview("Pickleball — 2 days ago") {
    SavedCourtCard(
        calibration: StoredCalibration(
            venueName: "Riverside · Court 3",
            layout: .regulationPickleball,
            imageCorners: [          // normalized [0,1], like production
                CodablePoint(x: 0.16, y: 0.80),
                CodablePoint(x: 0.84, y: 0.80),
                CodablePoint(x: 0.66, y: 0.30),
                CodablePoint(x: 0.34, y: 0.30),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-2 * 86_400)
        ),
        onStart: {},
        onReload: {}
    )
    .padding()
    .background(PVColor.paper)
}

#Preview("Tennis box — 5 hours ago") {
    SavedCourtCard(
        calibration: StoredCalibration(
            venueName: "Brighton Athletic · Court 1",
            layout: .tennisFrontBox,
            imageCorners: [          // normalized [0,1], like production
                CodablePoint(x: 0.18, y: 0.82),
                CodablePoint(x: 0.82, y: 0.82),
                CodablePoint(x: 0.64, y: 0.28),
                CodablePoint(x: 0.36, y: 0.28),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-5 * 3_600)
        ),
        onStart: {},
        onReload: {}
    )
    .padding()
    .background(PVColor.paper)
}

#Preview("Custom court — just now") {
    SavedCourtCard(
        calibration: StoredCalibration(
            venueName: "Backyard Setup",
            layout: .custom,
            imageCorners: [          // normalized [0,1], like production
                CodablePoint(x: 0.20, y: 0.78),
                CodablePoint(x: 0.80, y: 0.78),
                CodablePoint(x: 0.62, y: 0.32),
                CodablePoint(x: 0.38, y: 0.32),
            ],
            customDimensions: CustomDimensions(
                widthFeet: 18,
                lengthFeet: 38,
                nonVolleyZoneFeet: 6
            ),
            savedAt: Date().addingTimeInterval(-90)
        ),
        onStart: {},
        onReload: {}
    )
    .padding()
    .background(PVColor.paper)
}
