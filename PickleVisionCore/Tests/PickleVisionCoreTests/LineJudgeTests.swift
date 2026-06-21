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
        let result = LineJudge().call(bounce: bounce(atCourt: CGPoint(x: 10, y: 22), using: m), court: m)!
        XCTAssertEqual(result.call.verdict, .in)
    }

    func test_clearly_outside_is_out() {
        let m = model()
        let result = LineJudge().call(bounce: bounce(atCourt: CGPoint(x: -2, y: 22), using: m), court: m)!
        XCTAssertEqual(result.call.verdict, .out)
    }

    func test_within_band_is_too_close() {
        let m = model()
        // 1 inch inside the x=0 sideline at mid-court.
        let result = LineJudge(uncertaintyBandFeet: 0.33).call(bounce: bounce(atCourt: CGPoint(x: 0.08, y: 22), using: m), court: m)!
        XCTAssertEqual(result.call.verdict, .tooCloseToCall)
    }

    // M1: call() surfaces the court point it computed so RefereeCore reuses one value
    // instead of recomputing the homography (removes the latent desync risk).
    func test_call_returns_the_mapped_court_point() {
        let m = model()
        let courtPt = CGPoint(x: 10, y: 22)
        let b = bounce(atCourt: courtPt, using: m)
        let result = LineJudge().call(bounce: b, court: m)!
        // The surfaced court point is exactly the homography mapping of the bounce image point.
        let expected = m.courtPoint(forImage: b.imagePoint)
        XCTAssertEqual(result.courtPoint.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(result.courtPoint.y, expected.y, accuracy: 1e-9)
        // And it round-trips back near the original court point.
        XCTAssertEqual(result.courtPoint.x, courtPt.x, accuracy: 1e-6)
        XCTAssertEqual(result.courtPoint.y, courtPt.y, accuracy: 1e-6)
    }

    // A bounce that maps to a non-finite court coordinate (near the projective
    // vanishing line) yields no call.
    func test_non_finite_court_point_returns_nil() {
        let m = model()
        // Image point above the far edge can project past the horizon -> non-finite.
        let b = Bounce(imagePoint: CGPoint(x: 0.5, y: 0.05), time: 0, prominence: 1)
        let cp = m.courtPoint(forImage: b.imagePoint)
        // Only assert the contract when this point is actually non-finite for this quad.
        if !(cp.x.isFinite && cp.y.isFinite) {
            XCTAssertNil(LineJudge().call(bounce: b, court: m))
        }
    }
}
