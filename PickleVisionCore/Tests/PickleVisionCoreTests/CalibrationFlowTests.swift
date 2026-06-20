import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationFlowTests: XCTestCase {

    // CHECKS NEVER GATE: Continue works even with 0/3 checks passing.
    func test_continue_from_position_ignores_failing_checks() {
        var f = CalibrationFlow()
        f.checks = SetupChecks(steady: false, framed: false, angle: false)
        XCTAssertEqual(f.checks.passingCount, 0)
        f.continueFromPosition()
        XCTAssertEqual(f.step, .detect)   // advanced despite all checks failing
    }

    func test_continue_from_position_with_partial_checks() {
        var f = CalibrationFlow()
        f.checks = SetupChecks(steady: true, framed: true, angle: false)
        XCTAssertEqual(f.checks.passingCount, 2)
        XCTAssertEqual(f.checks.total, 3)
        f.continueFromPosition()
        XCTAssertEqual(f.step, .detect)
    }

    // FAILED AUTO-DETECT LEAVES MANUAL PATH REACHABLE.
    func test_failed_autodetect_keeps_manual_reachable() {
        var f = CalibrationFlow()
        f.startAutoDetect()
        XCTAssertEqual(f.autoDetect, .finding)
        XCTAssertEqual(f.step, .detect)
        f.resolveAutoDetect(.failed, detectedCorners: nil)
        XCTAssertEqual(f.autoDetect, .failed)
        XCTAssertEqual(f.step, .detect)        // not forced forward/back
        f.dropToManual()
        XCTAssertEqual(f.step, .fineTune)      // guaranteed manual path
        XCTAssertTrue(f.isComplete)            // default corners present
    }

    func test_calibrate_manually_skips_detect() {
        var f = CalibrationFlow()
        f.calibrateManually()
        XCTAssertEqual(f.step, .fineTune)
    }

    func test_found_autodetect_copies_detected_corners() {
        var f = CalibrationFlow()
        let detected = [CGPoint(x: 0.25, y: 0.88), CGPoint(x: 0.78, y: 0.88),
                        CGPoint(x: 0.63, y: 0.32), CGPoint(x: 0.37, y: 0.32)]
        f.startAutoDetect()
        f.resolveAutoDetect(.found, detectedCorners: detected)
        XCTAssertEqual(f.autoDetect, .found)
        XCTAssertEqual(f.corners, detected)
    }

    func test_step_order_advance_and_back_clamp() {
        var f = CalibrationFlow()
        XCTAssertEqual(f.step, .position)
        f.advance(); XCTAssertEqual(f.step, .detect)
        f.advance(); XCTAssertEqual(f.step, .fineTune)
        f.advance(); XCTAssertEqual(f.step, .verify)
        f.advance(); XCTAssertEqual(f.step, .verify)   // clamped
        f.back(); XCTAssertEqual(f.step, .fineTune)
        f.back(); XCTAssertEqual(f.step, .detect)
        f.back(); XCTAssertEqual(f.step, .position)
        f.back(); XCTAssertEqual(f.step, .position)    // clamped
    }

    func test_court_model_and_fit_quality_available_when_complete() {
        let f = CalibrationFlow()   // default corners are a valid quad
        XCTAssertNotNil(f.courtModel)
        XCTAssertEqual(f.cornersSetCount, 4)
        XCTAssertEqual(f.fitQuality.quality, .good)
    }

    func test_express_recal_lands_on_finetune_with_loaded_corners() {
        let saved = [CGPoint(x: 0.2, y: 0.9), CGPoint(x: 0.8, y: 0.9),
                     CGPoint(x: 0.65, y: 0.3), CGPoint(x: 0.35, y: 0.3)]
        let f = CalibrationFlow.forExpressReCal(corners: saved,
                                                layout: .tennisFrontBox,
                                                customDimensions: nil)
        XCTAssertEqual(f.step, .fineTune)
        XCTAssertEqual(f.corners, saved)
        XCTAssertEqual(f.layout, .tennisFrontBox)
        XCTAssertTrue(f.overlayVisible)
    }

    func test_custom_dimensions_flow_into_court_model() {
        var f = CalibrationFlow()
        f.layout = .custom
        f.customDimensions = CustomDimensions(widthFeet: 18, lengthFeet: 40, nonVolleyZoneFeet: 7)
        XCTAssertEqual(f.courtModel?.profile.widthFeet, 18)
        XCTAssertEqual(f.courtModel?.profile.lengthFeet, 40)
    }

    // OVERLAY DEFAULTS ON when a transition lands on a calibrating step (I3).
    func test_overlay_visible_after_calibrate_manually() {
        var f = CalibrationFlow()
        XCTAssertFalse(f.overlayVisible)        // .position
        f.calibrateManually()
        XCTAssertEqual(f.step, .fineTune)
        XCTAssertTrue(f.overlayVisible)
    }

    func test_overlay_visible_after_advancing_into_finetune() {
        var f = CalibrationFlow()
        f.advance()                              // .detect
        XCTAssertFalse(f.overlayVisible)
        f.advance()                              // .fineTune
        XCTAssertTrue(f.overlayVisible)
    }

    func test_overlay_visible_after_drop_to_manual() {
        var f = CalibrationFlow()
        f.startAutoDetect()
        f.resolveAutoDetect(.failed, detectedCorners: nil)
        f.dropToManual()
        XCTAssertTrue(f.overlayVisible)
    }

    // CORNER-COUNT VALIDATION (M4): wrong-count input never strands the drag UI.
    func test_invalid_corner_count_falls_back_to_defaults() {
        let f = CalibrationFlow(corners: [CGPoint(x: 0.1, y: 0.1)])   // only 1 corner
        XCTAssertEqual(f.corners.count, 4)
        XCTAssertEqual(f.corners, CalibrationDraft.defaultCorners())
    }

    func test_found_autodetect_with_invalid_corners_falls_back_to_failed() {
        var f = CalibrationFlow()
        f.startAutoDetect()
        f.resolveAutoDetect(.found, detectedCorners: [CGPoint(x: 0.2, y: 0.9)])  // wrong count
        XCTAssertEqual(f.autoDetect, .failed)
        XCTAssertEqual(f.step, .detect)          // not blocked; manual still reachable
    }
}
