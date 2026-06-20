import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class RefereeCoreTests: XCTestCase {

    // Court model from the same normalized quad used by LineJudgeTests.
    // Corners order: [nearLeft, nearRight, farRight, farLeft].
    private func model() -> CourtModel {
        let corners = [
            CGPoint(x: 0.18, y: 0.82),
            CGPoint(x: 0.82, y: 0.82),
            CGPoint(x: 0.64, y: 0.30),
            CGPoint(x: 0.36, y: 0.30)
        ]
        return CalibrationDraft(corners: corners, layout: .regulationPickleball).courtModel()!
    }

    // Build a short parabola segment (down-then-up in image-y) whose vertex sits at
    // `peakY` (max image-y = ball on ground). Returns 11 BallObservation values
    // starting at absolute time `t0`. Vertex is placed at local t=0.45, strictly
    // between samples i=4 (t=0.4) and i=5 (t=0.5), so the central-difference velocity
    // sign flip is geometric (real margin ~0.6 image-y/s), not floating-point noise.
    // y(t) = peakY - 40.0*(t - 0.45)^2:
    //   y[4] = peakY - 40*(0.4-0.45)^2 = peakY - 0.10 (clearly below peak)
    //   y[5] = peakY - 40*(0.5-0.45)^2 = peakY - 0.10 (clearly below peak)
    // Detected bounce time will be near t0+0.45.
    private func parabola(
        peakX: Double,
        peakY: Double,
        t0: TimeInterval,
        xDrift: Double = 0.05
    ) -> [BallObservation] {
        // y(t) = peakY - 40.0*(t - 0.45)^2; max image-y at t=0.45 (ball at ground).
        // Increasing image-y means ball moves DOWN the frame (image-space convention).
        var obs: [BallObservation] = []
        for i in 0...10 {
            let t = Double(i) * 0.1
            let y = peakY - 40.0 * (t - 0.45) * (t - 0.45)
            let x = peakX + xDrift * t
            obs.append(BallObservation(
                imagePoint: CGPoint(x: x, y: y),
                time: t0 + t,
                confidence: 1.0
            ))
        }
        return obs
    }

    // Synthetic two-bounce rally: bounce A is clearly INSIDE, bounce B is clearly OUTSIDE.
    // Two parabola segments (each 1 s) are separated by a 0.5 s gap (>maxGap=0.1 s)
    // so Tracker keeps them as disjoint runs and BounceDetector sees one bounce per segment.
    // Each segment vertex is at local t=0.45 (geometric, not float-noise), so:
    //   bounce A at absolute t~0.45, bounce B at absolute t~1.95.
    // The bounce image points are derived from known court points via model.imagePoint(forCourt:),
    // then verified by RefereeCore mapping them back through courtPoint(forImage:).
    func test_evaluate_returns_in_then_out_for_two_bounce_rally() {
        let m = model()

        // Court point clearly inside: center of court (10 ft, 22 ft).
        let insideCourtPt = CGPoint(x: 10.0, y: 22.0)
        // Court point clearly outside: well past the left sideline (-3 ft, 22 ft).
        let outsideCourtPt = CGPoint(x: -3.0, y: 22.0)

        guard
            let insideImg  = m.imagePoint(forCourt: insideCourtPt),
            let outsideImg = m.imagePoint(forCourt: outsideCourtPt)
        else {
            XCTFail("CourtModel failed to map court points to image")
            return
        }

        // Segment A: t in [0.0, 1.0], bounce near t=0.45 -- maps to inside court.
        let segA = parabola(peakX: insideImg.x,  peakY: insideImg.y,  t0: 0.0)
        // Segment B: t in [1.5, 2.5], bounce near t=1.95 -- maps to outside court.
        // 0.5 s gap between segments is > maxGap=0.1 s so Tracker leaves it as-is.
        let segB = parabola(peakX: outsideImg.x, peakY: outsideImg.y, t0: 1.5)

        let observations = segA + segB

        let result = RefereeCore().evaluate(observations, court: m)

        XCTAssertEqual(result.count, 2, "Expected exactly two judged bounces")
        guard result.count == 2 else { return }

        XCTAssertEqual(result[0].call.verdict, .in,  "First bounce should be IN")
        XCTAssertEqual(result[1].call.verdict, .out, "Second bounce should be OUT")
        XCTAssertLessThan(result[0].bounce.time, result[1].bounce.time, "Bounces should be in time order")
        XCTAssertTrue(result[0].courtPoint.x.isFinite && result[0].courtPoint.y.isFinite)
        XCTAssertTrue(result[1].courtPoint.x.isFinite && result[1].courtPoint.y.isFinite)
    }

    // Observations that yield no bounces should produce an empty result.
    func test_evaluate_empty_observations_returns_empty() {
        let m = model()
        let result = RefereeCore().evaluate([], court: m)
        XCTAssertTrue(result.isEmpty)
    }

    // Monotonic downward motion (no bounce) produces no judged bounces.
    func test_evaluate_monotonic_motion_returns_empty() {
        let m = model()
        let obs = (0...5).map {
            BallObservation(
                imagePoint: CGPoint(x: 0.5, y: 0.1 + 0.05 * Double($0)),
                time: Double($0) * 0.1,
                confidence: 1.0
            )
        }
        let result = RefereeCore().evaluate(obs, court: m)
        XCTAssertTrue(result.isEmpty)
    }
}
