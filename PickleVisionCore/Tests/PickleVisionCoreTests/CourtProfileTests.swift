import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CourtProfileTests: XCTestCase {
    func test_pickleball_dimensions_and_corners() {
        let p = CourtProfile.make(layout: .regulationPickleball)
        XCTAssertEqual(p.widthFeet, 20)
        XCTAssertEqual(p.lengthFeet, 44)
        XCTAssertEqual(p.nonVolleyZoneFeet, 7)
        XCTAssertEqual(p.calibrationCorners,
                       [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0),
                        CGPoint(x: 20, y: 44), CGPoint(x: 0, y: 44)])
        XCTAssertEqual(p.inBoundsPolygon, p.calibrationCorners)
    }

    func test_pickleball_net_and_nvz_lines() {
        let p = CourtProfile.make(layout: .regulationPickleball)
        XCTAssertEqual(p.netLine, [CGPoint(x: 0, y: 22), CGPoint(x: 20, y: 22)])
        XCTAssertEqual(p.nvzLines.count, 2)
        XCTAssertEqual(p.nvzLines[0], [CGPoint(x: 0, y: 15), CGPoint(x: 20, y: 15)])
        XCTAssertEqual(p.nvzLines[1], [CGPoint(x: 0, y: 29), CGPoint(x: 20, y: 29)])
    }

    func test_tennis_front_box_dimensions() {
        let p = CourtProfile.make(layout: .tennisFrontBox)
        XCTAssertEqual(p.widthFeet, 27)
        XCTAssertEqual(p.lengthFeet, 42)
        XCTAssertEqual(p.netLine, [CGPoint(x: 0, y: 21), CGPoint(x: 27, y: 21)])
        XCTAssertEqual(p.nonVolleyZoneFeet, 7)
        XCTAssertEqual(p.nvzLines[0], [CGPoint(x: 0, y: 14), CGPoint(x: 27, y: 14)])
        XCTAssertEqual(p.nvzLines[1], [CGPoint(x: 0, y: 28), CGPoint(x: 27, y: 28)])
    }

    func test_custom_uses_supplied_dimensions() {
        let p = CourtProfile.make(layout: .custom,
                                  custom: CustomDimensions(widthFeet: 24, lengthFeet: 50, nonVolleyZoneFeet: 6))
        XCTAssertEqual(p.widthFeet, 24)
        XCTAssertEqual(p.lengthFeet, 50)
        XCTAssertEqual(p.netLine, [CGPoint(x: 0, y: 25), CGPoint(x: 24, y: 25)])
        XCTAssertEqual(p.nvzLines[0], [CGPoint(x: 0, y: 19), CGPoint(x: 24, y: 19)])
        XCTAssertEqual(p.nvzLines[1], [CGPoint(x: 0, y: 31), CGPoint(x: 24, y: 31)])
    }
}
