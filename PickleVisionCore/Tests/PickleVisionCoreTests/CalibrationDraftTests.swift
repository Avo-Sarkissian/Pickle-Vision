import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationDraftTests: XCTestCase {
    private func sampleCorners() -> [CGPoint] {
        // A trapezoid in normalized image space (near edge lower/wider).
        [CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.80, y: 0.90),
         CGPoint(x: 0.65, y: 0.30), CGPoint(x: 0.35, y: 0.30)]
    }

    func test_incomplete_until_four_corners() {
        var d = CalibrationDraft(layout: .regulationPickleball)
        XCTAssertFalse(d.isComplete)
        d.corners = sampleCorners()
        XCTAssertTrue(d.isComplete)
    }

    func test_builds_court_model_mapping_corner_to_origin() {
        let d = CalibrationDraft(corners: sampleCorners(), layout: .regulationPickleball)
        let model = try! XCTUnwrap(d.courtModel())
        // nearLeft normalized corner maps to court origin (0,0).
        let c = model.courtPoint(forImage: CGPoint(x: 0.20, y: 0.90))
        XCTAssertEqual(c.x, 0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 0, accuracy: 1e-6)
        XCTAssertEqual(model.profile.layout, .regulationPickleball)
    }

    func test_nil_court_model_when_incomplete() {
        XCTAssertNil(CalibrationDraft(layout: .regulationPickleball).courtModel())
    }

    func test_nearest_corner_within_radius() {
        let handles = [CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10),
                       CGPoint(x: 200, y: 200), CGPoint(x: 10, y: 200)]
        let d = CalibrationDraft(layout: .regulationPickleball)
        XCTAssertEqual(d.nearestCornerIndex(toView: CGPoint(x: 14, y: 13), handles: handles, within: 30), 0)
        XCTAssertNil(d.nearestCornerIndex(toView: CGPoint(x: 100, y: 100), handles: handles, within: 30))
    }

    func test_default_corners_are_four_inside_unit_square() {
        let c = CalibrationDraft.defaultCorners()
        XCTAssertEqual(c.count, 4)
        XCTAssertTrue(c.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}
