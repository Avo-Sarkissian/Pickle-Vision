import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class HomographyTests: XCTestCase {
    // A perspective-ish image trapezoid mapped to a 20x44 court rectangle.
    private let imageCorners = [
        CGPoint(x: 45,  y: 172),  // nearLeft
        CGPoint(x: 275, y: 172),  // nearRight
        CGPoint(x: 200, y: 48),   // farRight
        CGPoint(x: 120, y: 48),   // farLeft
    ]
    private let courtCorners = [
        CGPoint(x: 0,  y: 0),
        CGPoint(x: 20, y: 0),
        CGPoint(x: 20, y: 44),
        CGPoint(x: 0,  y: 44),
    ]

    func test_maps_each_corner_to_its_destination() {
        let h = try! XCTUnwrap(Homography(source: imageCorners, destination: courtCorners))
        for (img, court) in zip(imageCorners, courtCorners) {
            let p = h.project(img)
            XCTAssertEqual(p.x, court.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, court.y, accuracy: 1e-6)
        }
    }

    func test_inverse_round_trips_arbitrary_points() {
        let h = try! XCTUnwrap(Homography(source: imageCorners, destination: courtCorners))
        let inv = try! XCTUnwrap(h.inverse)
        for img in [CGPoint(x: 150, y: 120), CGPoint(x: 210, y: 90), CGPoint(x: 100, y: 160)] {
            let court = h.project(img)
            let back = inv.project(court)
            XCTAssertEqual(back.x, img.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, img.y, accuracy: 1e-6)
        }
    }

    func test_wrong_point_count_returns_nil() {
        XCTAssertNil(Homography(source: Array(imageCorners.prefix(3)), destination: courtCorners))
    }

    func test_degenerate_collinear_source_returns_nil() {
        let collinear = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                         CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0)]
        XCTAssertNil(Homography(source: collinear, destination: courtCorners))
    }
}
