import CoreGraphics
import Foundation

/// A v1, honesty-rule-compliant calibration *plausibility* indicator. It does
/// NOT claim per-zone accuracy (that is a Phase-2, measured-on-court number).
/// Instead it scores how plausible the four tapped corners are as a perspective
/// view of a real rectangular court, so a sloppy / mis-ordered / off-centre
/// placement reads worse than a clean one.
///
/// Why not a reprojection residual? A 4-point DLT is exactly determined, so
/// reprojecting the very corners it was fit from returns ~0 for ANY non-degenerate
/// quad — the residual carried no information and always read "Good". This metric
/// is computed purely from the quad's shape and genuinely varies with placement.
public enum FitQuality: Equatable {
    case good
    case fair

    /// Convenience segment count for callers that already hold a `FitQuality`.
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
    /// ([nearLeft, nearRight, farRight, farLeft]). Returns a qualitative bucket
    /// plus a unitless plausibility `score` in [0, 1] (lower = better), or
    /// `.infinity` for a degenerate / mis-ordered / non-convex quad. The label
    /// and the bar are both derived from `barSegments(for:)`, so they can never
    /// disagree.
    public static func evaluate(corners: [CGPoint],
                                layout: CourtLayout,
                                customDimensions: CustomDimensions? = nil)
    -> (quality: FitQuality, score: Double) {
        let s = plausibilityScore(corners)
        let q: FitQuality = barSegments(for: s) >= 3 ? .good : .fair
        return (q, s)
    }

    /// 0...4 segments for the bar, given a plausibility score (lower = better).
    /// Single source of truth for both the bar and the qualitative label.
    public static func barSegments(for score: Double) -> Int {
        guard score.isFinite else { return 0 }
        if score <= 0.10 { return 4 }
        if score <= 0.20 { return 3 }
        if score <= 0.35 { return 2 }
        return 1
    }

    /// Plausibility of the quad as a perspective image of a rectangle: combines
    /// top/bottom level-ness with left/right symmetry. Returns `.infinity` when
    /// the quad is degenerate (too small), mis-ordered, or non-convex
    /// (self-intersecting) — which is exactly the placement that should read worst.
    static func plausibilityScore(_ corners: [CGPoint]) -> Double {
        guard corners.count == 4 else { return .infinity }
        let p = corners.map { (x: Double($0.x), y: Double($0.y)) }

        func sub(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> (x: Double, y: Double) {
            (x: a.x - b.x, y: a.y - b.y)
        }
        func len(_ v: (x: Double, y: Double)) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
        func cross(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double { a.x * b.y - a.y * b.x }

        // Edge vectors around the quad NL->NR->FR->FL->NL.
        let e = [sub(p[1], p[0]), sub(p[2], p[1]), sub(p[3], p[2]), sub(p[0], p[3])]
        let lens = e.map(len)
        guard let minLen = lens.min(), minLen > 0.03 else { return .infinity }

        // Convexity / correct winding: all four turn cross-products share one sign.
        let turns = (0..<4).map { cross(e[$0], e[($0 + 1) % 4]) }
        let pos = turns.filter { $0 > 0 }.count
        let neg = turns.filter { $0 < 0 }.count
        guard pos == 4 || neg == 4 else { return .infinity }

        // Top/bottom level-ness: bottom edge (NL->NR) vs top edge (FL->FR) should
        // be near-parallel for a level (un-rolled) camera.
        let bottom = e[0]                    // NL -> NR
        let top    = sub(p[2], p[3])         // FL -> FR
        let denomTB = len(bottom) * len(top)
        let cosTB = denomTB > 0 ? max(-1, min(1, (bottom.x * top.x + bottom.y * top.y) / denomTB)) : 1
        let skewTB = min(acos(cosTB) / (Double.pi / 4), 1)   // 0 at parallel, 1 at >= 45 deg

        // Left/right symmetry: side edges should foreshorten ~equally for a
        // centred mount. lens[3] = FL->NL (left), lens[1] = NR->FR (right).
        let left = lens[3], right = lens[1]
        let imbalance = max(left, right) > 0 ? min(abs(left - right) / max(left, right), 1) : 1

        return 0.5 * skewTB + 0.5 * imbalance
    }
}
