import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class FitQualityTests: XCTestCase {
    // A clean, centred perspective trapezoid in normalized image space
    // ([nearLeft, nearRight, farRight, farLeft]).
    private func cleanCorners() -> [CGPoint] {
        [CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.80, y: 0.90),
         CGPoint(x: 0.65, y: 0.30), CGPoint(x: 0.35, y: 0.30)]
    }

    func test_clean_quad_is_good_full_segments() {
        let (q, score) = FitQuality.evaluate(corners: cleanCorners(),
                                             layout: .regulationPickleball)
        XCTAssertEqual(q, .good)
        XCTAssertEqual(FitQuality.barSegments(for: score), 4)
        XCTAssertEqual(q.label, "Good")
        XCTAssertLessThanOrEqual(score, 0.10)
    }

    func test_degenerate_collinear_quad_is_fair_zero_segments() {
        // Four collinear points -> no valid quad.
        let collinear = [CGPoint(x: 0.10, y: 0.50), CGPoint(x: 0.40, y: 0.50),
                         CGPoint(x: 0.70, y: 0.50), CGPoint(x: 0.95, y: 0.50)]
        let (q, score) = FitQuality.evaluate(corners: collinear,
                                             layout: .regulationPickleball)
        XCTAssertEqual(q, .fair)
        XCTAssertEqual(FitQuality.barSegments(for: score), 0)
        XCTAssertFalse(score.isFinite)
    }

    func test_wrong_corner_count_is_fair_zero_segments() {
        let (q, score) = FitQuality.evaluate(corners: [CGPoint(x: 0.2, y: 0.9)],
                                             layout: .regulationPickleball)
        XCTAssertEqual(q, .fair)
        XCTAssertEqual(FitQuality.barSegments(for: score), 0)
    }

    func test_custom_layout_clean_quad_is_good() {
        let dims = CustomDimensions(widthFeet: 18, lengthFeet: 40, nonVolleyZoneFeet: 7)
        let (q, _) = FitQuality.evaluate(corners: cleanCorners(),
                                         layout: .custom, customDimensions: dims)
        XCTAssertEqual(q, .good)
    }

    // Regression for the I2 bug: the OLD reprojection-residual metric scored this
    // self-intersecting "bowtie" (far corners swapped) as Good 4/4 because a
    // 4-point fit reprojects its own corners. The shape-based metric rejects it.
    func test_bowtie_quad_is_fair_zero_segments() {
        let bowtie = [CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.80, y: 0.90),
                      CGPoint(x: 0.35, y: 0.30), CGPoint(x: 0.65, y: 0.30)]
        let (q, score) = FitQuality.evaluate(corners: bowtie,
                                             layout: .regulationPickleball)
        XCTAssertEqual(q, .fair)
        XCTAssertEqual(FitQuality.barSegments(for: score), 0)
    }

    // The metric must actually VARY with placement: a lopsided (but still convex)
    // quad must score worse than a clean one and not read as full "Good".
    func test_skewed_convex_quad_scores_below_clean() {
        let skewed = [CGPoint(x: 0.15, y: 0.90), CGPoint(x: 0.80, y: 0.85),
                      CGPoint(x: 0.60, y: 0.32), CGPoint(x: 0.42, y: 0.45)]
        let (_, score) = FitQuality.evaluate(corners: skewed,
                                             layout: .regulationPickleball)
        let cleanScore = FitQuality.plausibilityScore(cleanCorners())
        XCTAssertLessThan(FitQuality.barSegments(for: score), 4)
        XCTAssertGreaterThan(score, cleanScore)
    }

    // M2: label and bar are derived from one ladder, so they cannot disagree.
    func test_label_and_bar_share_one_source_of_truth() {
        let (q, score) = FitQuality.evaluate(corners: cleanCorners(),
                                             layout: .regulationPickleball)
        XCTAssertEqual(q == .good, FitQuality.barSegments(for: score) >= 3)
        XCTAssertEqual(FitQuality.good.label, "Good")
        XCTAssertEqual(FitQuality.fair.label, "Fair")
    }
}
