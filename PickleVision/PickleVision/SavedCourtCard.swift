import SwiftUI
import PickleVisionCore

/// One saved-court row on Home: mini court thumbnail + venue + a single
/// metadata line (layout · dimensions · relative save date) + a reload (↻)
/// affordance. Shows ONLY persisted fields (honesty rule).
struct SavedCourtCard: View {
    let calibration: StoredCalibration
    let onReload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CourtThumbnail(calibration: calibration)
                .frame(width: 56, height: 44)

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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(PVColor.panel)
            if let model = courtModel {
                CourtOverlay(model: model,
                             imageSize: imageSize(calibration),
                             lineWidth: 1.2,
                             opacity: 1.0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var courtModel: CourtModel? {
        let store = CalibrationStore(directory: URL.documentsDirectory
            .appendingPathComponent("calibrations"))
        return store.courtModel(from: calibration)
    }

    // Thumbnail draws in image space; use the corners' bounding box as the
    // content size so the overlay's AspectFillMapper frames the court.
    private func imageSize(_ cal: StoredCalibration) -> CGSize {
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
            imageCorners: [
                CodablePoint(x: 45,  y: 172),
                CodablePoint(x: 275, y: 172),
                CodablePoint(x: 200, y: 48),
                CodablePoint(x: 120, y: 48),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-2 * 86_400)
        ),
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
            imageCorners: [
                CodablePoint(x: 60,  y: 200),
                CodablePoint(x: 320, y: 200),
                CodablePoint(x: 260, y: 50),
                CodablePoint(x: 120, y: 50),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-5 * 3_600)
        ),
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
            imageCorners: [
                CodablePoint(x: 80,  y: 180),
                CodablePoint(x: 300, y: 180),
                CodablePoint(x: 240, y: 60),
                CodablePoint(x: 140, y: 60),
            ],
            customDimensions: CustomDimensions(
                widthFeet: 18,
                lengthFeet: 38,
                nonVolleyZoneFeet: 6
            ),
            savedAt: Date().addingTimeInterval(-90)
        ),
        onReload: {}
    )
    .padding()
    .background(PVColor.paper)
}
