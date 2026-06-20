import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class FitQualityTests: XCTestCase {
    // A clean perspective trapezoid in normalized image space
    // ([nearLeft, nearRight, farRight, farLeft]).
    private func cleanCorners() -> [CGPoint] {
        [CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.80, y: 0.90),
         CGPoint(x: 0.65, y: 0.30), CGPoint(x: 0.35, y: 0.30)]
    }

    func test_clean_quad_is_good_full_segments() {
        let (q, residual) = FitQuality.evaluate(corners: cleanCorners(),
                                                layout: .regulationPickleball)
        XCTAssertEqual(q, .good)
        XCTAssertEqual(q.segments, 4)
        XCTAssertEqual(q.label, "Good")
        XCTAssertLessThanOrEqual(residual, 1e-6)
    }

    func test_degenerate_collinear_quad_is_fair_zero_segments() {
        // Four nearly-collinear points -> no valid homography.
        let collinear = [CGPoint(x: 0.10, y: 0.50), CGPoint(x: 0.40, y: 0.50),
                         CGPoint(x: 0.70, y: 0.50), CGPoint(x: 0.95, y: 0.50)]
        let (q, residual) = FitQuality.evaluate(corners: collinear,
                                                layout: .regulationPickleball)
        XCTAssertEqual(q, .fair)
        XCTAssertEqual(FitQuality.barSegments(for: residual), 0)
        XCTAssertEqual(q.label, "Fair")
        XCTAssertFalse(residual.isFinite || residual <= 1e-2 && residual >= 0 && q == .good)
    }

    func test_wrong_corner_count_is_fair_zero_segments() {
        let (q, residual) = FitQuality.evaluate(corners: [CGPoint(x: 0.2, y: 0.9)],
                                                layout: .regulationPickleball)
        XCTAssertEqual(q, .fair)
        XCTAssertEqual(FitQuality.barSegments(for: residual), 0)
    }

    func test_custom_layout_clean_quad_is_good() {
        let dims = CustomDimensions(widthFeet: 18, lengthFeet: 40, nonVolleyZoneFeet: 7)
        let (q, _) = FitQuality.evaluate(corners: cleanCorners(),
                                         layout: .custom, customDimensions: dims)
        XCTAssertEqual(q, .good)
        XCTAssertEqual(q.segments, 4)
    }

    func test_segments_and_label_are_consistent() {
        XCTAssertEqual(FitQuality.good.label, "Good")
        XCTAssertEqual(FitQuality.fair.label, "Fair")
    }
}
