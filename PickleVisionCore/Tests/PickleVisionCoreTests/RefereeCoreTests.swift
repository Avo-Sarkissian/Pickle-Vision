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
    // starting at absolute time `t0`. Formula matches BounceDetectorTests: the
    // coefficient 4.0 is large enough that floating-point asymmetry around t=0.5
    // reliably produces a tiny negative velocity at the sample just past the peak,
    // triggering BounceDetector's sign-flip criterion. The bounce occurs at t0+0.5.
    private func parabola(
        peakX: Double,
        peakY: Double,
        t0: TimeInterval,
        xDrift: Double = 0.05
    ) -> [BallObservation] {
        // y(t) = peakY - 4.0*(t - 0.5)^2
        // At t=0.5: y = peakY (maximum image-y = ball at ground = bounce).
        // At t=0 and t=1: y = peakY - 1.0 (ball is in air, smaller image-y).
        // Increasing image-y means ball moves DOWN the frame (image-space convention).
        var obs: [BallObservation] = []
        for i in 0...10 {
            let t = Double(i) * 0.1
            let y = peakY - 4.0 * (t - 0.5) * (t - 0.5)
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

        // Segment A: t in [0.0, 1.0], bounce at t=0.5 -- maps to inside court.
        let segA = parabola(peakX: insideImg.x,  peakY: insideImg.y,  t0: 0.0)
        // Segment B: t in [1.5, 2.5], bounce at t=2.0 -- maps to outside court.
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
