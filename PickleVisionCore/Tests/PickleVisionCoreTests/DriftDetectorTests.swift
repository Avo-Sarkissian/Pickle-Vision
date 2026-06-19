import XCTest
@testable import PickleVisionCore

final class DriftDetectorTests: XCTestCase {
    func test_small_motion_is_stable() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 5, rotationRadians: 0.005), .stable)
    }

    func test_large_translation_is_drift() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 20, rotationRadians: 0), .drifted)
    }

    func test_large_rotation_is_drift() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 0, rotationRadians: -0.05), .drifted)
    }

    func test_threshold_is_inclusive() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 12, rotationRadians: 0), .drifted)
    }
}
