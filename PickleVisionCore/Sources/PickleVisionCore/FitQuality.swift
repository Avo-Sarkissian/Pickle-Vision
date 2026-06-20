import CoreGraphics

/// A v1, honesty-rule-compliant fit indicator: a qualitative bucket plus a
/// 0–4 segment count for the bar, derived from the homography reprojection
/// residual of the four calibrated corners. We surface only the label and the
/// bar in the UI — never the raw residual — because per-zone ± inches are a
/// Phase-2 (measured-on-court) number we cannot produce yet.
public enum FitQuality: Equatable {
    case good
    case fair

    /// Convenience segment count for callers that already hold a `FitQuality`.
    /// `.good` → 4; `.fair` → 1 (the bar uses `barSegments(for:)` for 0–4 resolution).
    public var segments: Int {
        switch self {
        case .good: return 4
        case .fair: return 1
        }
    }

    /// Qualitative label shown in the UI.
    public var label: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        }
    }

    /// Evaluates fit quality from the 4 *normalized* image corners
    /// ([nearLeft, nearRight, farRight, farLeft]) for the given layout.
    /// Reprojection residual = mean distance, in normalized image units,
    /// between each input corner and the corner reprojected by the inverse
    /// homography (court corner -> image). Degenerate corners -> .fair / 0 segs.
    public static func evaluate(corners: [CGPoint],
                                layout: CourtLayout,
                                customDimensions: CustomDimensions? = nil)
    -> (quality: FitQuality, residual: Double) {
        let r = computeResidual(corners: corners, layout: layout, customDimensions: customDimensions)
        let q: FitQuality = (r <= 1e-3) ? .good : .fair
        return (q, r)
    }

    /// 0...4 segments for the bar, given a residual (normalized image units).
    /// Use this in the view-model/bar UI so the bar can show 0 for degenerate inputs.
    public static func barSegments(for residual: Double) -> Int {
        guard residual.isFinite else { return 0 }
        if residual <= 1e-6 { return 4 }
        if residual <= 1e-3 { return 3 }
        if residual <= 1e-2 { return 2 }
        return 1
    }

    /// Mean reprojection distance, in normalized image units, between each
    /// input corner and the corresponding court corner mapped back to image
    /// space via the inverse homography. `.infinity` when no homography exists.
    private static func computeResidual(corners: [CGPoint],
                                        layout: CourtLayout,
                                        customDimensions: CustomDimensions?) -> Double {
        guard corners.count == 4 else { return .infinity }
        let profile = CourtProfile.make(layout: layout, custom: customDimensions)
        guard let h = Homography(source: corners, destination: profile.calibrationCorners),
              let inv = h.inverse else { return .infinity }
        var sum = 0.0
        for i in 0..<4 {
            let back = inv.project(profile.calibrationCorners[i])
            sum += hypot(Double(back.x - corners[i].x), Double(back.y - corners[i].y))
        }
        return sum / 4.0
    }
}
