import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CourtModelTests: XCTestCase {
    private func makeModel() -> CourtModel {
        let profile = CourtProfile.make(layout: .regulationPickleball)
        let imageCorners = [
            CGPoint(x: 45, y: 172), CGPoint(x: 275, y: 172),
            CGPoint(x: 200, y: 48), CGPoint(x: 120, y: 48),
        ]
        let h = Homography(source: imageCorners, destination: profile.calibrationCorners)!
        return CourtModel(profile: profile, homography: h)
    }

    func test_image_corner_maps_to_court_origin() {
        let model = makeModel()
        let c = model.courtPoint(forImage: CGPoint(x: 45, y: 172))
        XCTAssertEqual(c.x, 0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 0, accuracy: 1e-6)
    }

    func test_court_to_image_round_trip() throws {
        let model = makeModel()
        let img = try XCTUnwrap(model.imagePoint(forCourt: CGPoint(x: 20, y: 44)))
        XCTAssertEqual(img.x, 200, accuracy: 1e-6)
        XCTAssertEqual(img.y, 48, accuracy: 1e-6)
    }

    func test_in_bounds_point() {
        let model = makeModel()
        XCTAssertTrue(model.isInBounds(courtPoint: CGPoint(x: 10, y: 22)))
    }

    func test_out_of_bounds_point() {
        let model = makeModel()
        XCTAssertFalse(model.isInBounds(courtPoint: CGPoint(x: 21, y: 22))) // past sideline
        XCTAssertFalse(model.isInBounds(courtPoint: CGPoint(x: 10, y: 45))) // past baseline
    }
}
