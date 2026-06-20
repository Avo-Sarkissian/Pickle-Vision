import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class BounceDetectorTests: XCTestCase {
    // Ball falls (image-y increasing) to a low point then rises: one bounce.
    // Vertex is placed at t=0.45, strictly between samples i=4 (t=0.4) and i=5 (t=0.5),
    // so y[4] and y[5] are both measurably below the peak and the central-difference
    // velocity sign flip is determined by geometry, not floating-point rounding noise.
    // y(t) = 0.9 - 40*(t - 0.45)^2:
    //   y[4] = 0.9 - 40*(0.4-0.45)^2 = 0.9 - 40*0.0025 = 0.9 - 0.1  = 0.80
    //   y[5] = 0.9 - 40*(0.5-0.45)^2 = 0.9 - 40*0.0025 = 0.9 - 0.1  = 0.80
    //   dy before vertex (i=4): (y[5]-y[3])/0.2 ~ (0.80-0.676)/0.2 > 0 (moving down in image)
    //   dy after  vertex (i=5): (y[6]-y[4])/0.2 ~ (0.676-0.80)/0.2  < 0 (moving up  in image)
    // The sign flip is ~0.6 image-units/s, not ~1e-16 noise.
    private func parabolaTrack() -> BallTrack {
        // y(t) peaks (max image-y) at t=0.45; x drifts right.
        var obs: [BallObservation] = []
        for i in 0...10 {
            let t = Double(i) * 0.1
            let y = 0.9 - 40.0 * (t - 0.45) * (t - 0.45)   // max at t=0.45, y=0.9
            obs.append(BallObservation(imagePoint: CGPoint(x: 0.2 + 0.05 * t, y: y), time: t, confidence: 1))
        }
        return Tracker().track(obs)
    }

    func test_detects_single_bounce_near_low_point() {
        let bounces = BounceDetector().bounces(in: parabolaTrack())
        XCTAssertEqual(bounces.count, 1)
        // Vertex is at t=0.45; BounceDetector reports the sample nearest the peak.
        // The two samples bracketing the vertex (t=0.4 and t=0.5) are both at peakY - 0.10 = 0.80,
        // so the detected y is 0.80 and the detected time is 0.4 or 0.5 (within 0.06 of 0.45).
        XCTAssertEqual(bounces[0].time, 0.45, accuracy: 0.06)
        XCTAssertEqual(bounces[0].imagePoint.y, 0.9, accuracy: 0.11)
    }

    func test_monotonic_motion_has_no_bounce() {
        let obs = (0...5).map { BallObservation(imagePoint: CGPoint(x: 0.2, y: 0.1 + 0.1 * Double($0)), time: Double($0) * 0.1, confidence: 1) }
        XCTAssertTrue(BounceDetector().bounces(in: Tracker().track(obs)).isEmpty)
    }
}
