import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class TrackerTests: XCTestCase {
    private func obs(_ x: Double, _ y: Double, _ t: Double, _ c: Double = 1) -> BallObservation {
        BallObservation(imagePoint: CGPoint(x: x, y: y), time: t, confidence: c)
    }

    func test_low_confidence_observations_dropped() {
        let track = Tracker().track([obs(0.1,0.1,0), obs(0.9,0.9,0.01,0.05), obs(0.2,0.2,0.02)])
        XCTAssertEqual(track.samples.count, 2)   // the 0.05-confidence outlier is dropped
    }

    func test_velocity_is_finite_difference() {
        // Constant rightward motion: x = t, y = 0.5
        let track = Tracker().track([obs(0.0,0.5,0), obs(0.1,0.5,0.1), obs(0.2,0.5,0.2)])
        let mid = track.samples[1]
        XCTAssertEqual(mid.velocity.dx, 1.0, accuracy: 1e-6)   // 0.2 over 0.2s
        XCTAssertEqual(mid.velocity.dy, 0.0, accuracy: 1e-6)
    }

    func test_spatial_outlier_rejected() {
        let track = Tracker().track([obs(0.10,0.5,0), obs(0.95,0.5,0.01), obs(0.12,0.5,0.02), obs(0.14,0.5,0.03)])
        XCTAssertFalse(track.samples.contains { abs($0.imagePoint.x - 0.95) < 1e-9 })
    }
}
