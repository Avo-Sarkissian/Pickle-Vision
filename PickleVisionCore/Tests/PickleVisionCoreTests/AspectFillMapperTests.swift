import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class AspectFillMapperTests: XCTestCase {
    // Square 100x100 content shown in a 200x100 (wide) view → scale 2x, vertical overflow cropped.
    private let mapper = AspectFillMapper(viewSize: CGSize(width: 200, height: 100),
                                          contentSize: CGSize(width: 100, height: 100))

    func test_view_center_maps_to_image_center() {
        let n = mapper.imageNormalized(fromView: CGPoint(x: 100, y: 50))
        XCTAssertEqual(n.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.5, accuracy: 1e-9)
    }

    func test_view_top_left_is_inside_cropped_image() {
        // Vertical content is cropped: view y=0 sits 25% down the image.
        let n = mapper.imageNormalized(fromView: CGPoint(x: 0, y: 0))
        XCTAssertEqual(n.x, 0.0, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.25, accuracy: 1e-9)
    }

    func test_round_trips() {
        for p in [CGPoint(x: 30, y: 20), CGPoint(x: 175, y: 80), CGPoint(x: 100, y: 50)] {
            let back = mapper.view(fromImageNormalized: mapper.imageNormalized(fromView: p))
            XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
        }
    }

    func test_tall_view_crops_horizontally() {
        // 100x100 content in a 100x200 (tall) view → scale 2x, horizontal overflow cropped.
        let m = AspectFillMapper(viewSize: CGSize(width: 100, height: 200),
                                 contentSize: CGSize(width: 100, height: 100))
        let n = m.imageNormalized(fromView: CGPoint(x: 0, y: 100)) // left edge, vertical center
        XCTAssertEqual(n.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.5, accuracy: 1e-9)
    }

    func test_degenerate_sizes_do_not_nan() {
        let m = AspectFillMapper(viewSize: .zero, contentSize: CGSize(width: 100, height: 100))
        let n = m.imageNormalized(fromView: CGPoint(x: 10, y: 10))
        XCTAssertTrue(n.x.isFinite && n.y.isFinite)
        let v = m.view(fromImageNormalized: CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(v.x.isFinite && v.y.isFinite)
    }
}
