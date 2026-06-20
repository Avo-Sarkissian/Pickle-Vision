import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class BounceDetectorTests: XCTestCase {
    // Ball falls (image-y increasing) to a low point then rises: one bounce.
    private func parabolaTrack() -> BallTrack {
        // y(t) peaks (max image-y) at t=0.5; x drifts right.
        var obs: [BallObservation] = []
        for i in 0...10 {
            let t = Double(i) * 0.1
            let y = 0.9 - 4 * (t - 0.5) * (t - 0.5)   // max at t=0.5, y=0.9
            obs.append(BallObservation(imagePoint: CGPoint(x: 0.2 + 0.05 * t, y: y), time: t, confidence: 1))
        }
        return Tracker().track(obs)
    }

    func test_detects_single_bounce_near_low_point() {
        let bounces = BounceDetector().bounces(in: parabolaTrack())
        XCTAssertEqual(bounces.count, 1)
        XCTAssertEqual(bounces[0].time, 0.5, accuracy: 0.06)
        XCTAssertEqual(bounces[0].imagePoint.y, 0.9, accuracy: 0.02)
    }

    func test_monotonic_motion_has_no_bounce() {
        let obs = (0...5).map { BallObservation(imagePoint: CGPoint(x: 0.2, y: 0.1 + 0.1 * Double($0)), time: Double($0) * 0.1, confidence: 1) }
        XCTAssertTrue(BounceDetector().bounces(in: Tracker().track(obs)).isEmpty)
    }
}
