import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class LineJudgeTests: XCTestCase {
    // Court model from a clean normalized quad (regulation 20x44).
    private func model() -> CourtModel {
        let corners = [CGPoint(x:0.18,y:0.82), CGPoint(x:0.82,y:0.82), CGPoint(x:0.64,y:0.30), CGPoint(x:0.36,y:0.30)]
        return CalibrationDraft(corners: corners, layout: .regulationPickleball).courtModel()!
    }
    private func bounce(atCourt c: CGPoint, using m: CourtModel) -> Bounce {
        Bounce(imagePoint: m.imagePoint(forCourt: c)!, time: 0, prominence: 1)
    }

    func test_clearly_inside_is_in() {
        let m = model()
        let call = LineJudge().call(bounce: bounce(atCourt: CGPoint(x: 10, y: 22), using: m), court: m)!
        XCTAssertEqual(call.verdict, .in)
    }

    func test_clearly_outside_is_out() {
        let m = model()
        let call = LineJudge().call(bounce: bounce(atCourt: CGPoint(x: -2, y: 22), using: m), court: m)!
        XCTAssertEqual(call.verdict, .out)
    }

    func test_within_band_is_too_close() {
        let m = model()
        // 1 inch inside the x=0 sideline at mid-court.
        let call = LineJudge(uncertaintyBandFeet: 0.33).call(bounce: bounce(atCourt: CGPoint(x: 0.08, y: 22), using: m), court: m)!
        XCTAssertEqual(call.verdict, .tooCloseToCall)
    }
}
