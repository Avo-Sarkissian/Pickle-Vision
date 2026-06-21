import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class EvalRunnerTests: XCTestCase {

    // Build a JudgedBounce directly (court point + verdict + time) so the runner is
    // tested in isolation from RefereeCore / CourtModel.
    private func pred(_ court: CGPoint, _ verdict: LineVerdict, _ time: TimeInterval) -> JudgedBounce {
        JudgedBounce(
            bounce: Bounce(imagePoint: .zero, time: time, prominence: 1),
            courtPoint: court,
            call: LineCall(verdict: verdict, distanceToLineFeet: 0, uncertaintyBandFeet: 0.33)
        )
    }
    private func ref(_ court: CGPoint, _ verdict: LineVerdict, _ time: TimeInterval) -> ReferenceBounce {
        ReferenceBounce(courtPoint: court, expectedVerdict: verdict, time: time)
    }

    private let inPt  = CGPoint(x: 10, y: 22)
    private let outPt = CGPoint(x: -2, y: 22)

    func test_perfect_match_all_clear_correct() {
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .in, 1.0), pred(outPt, .out, 2.0)],
            reference: [ref(inPt, .in, 1.0),  ref(outPt, .out, 2.0)]
        )
        XCTAssertEqual(report.matchedCount, 2)
        XCTAssertEqual(report.falsePositives, 0)
        XCTAssertEqual(report.falseNegatives, 0)
        XCTAssertEqual(report.bouncePrecision, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.bounceRecall, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.clearCallTotal, 2)
        XCTAssertEqual(report.clearCallCorrect, 2)
        XCTAssertEqual(report.clearCallWrong, 0)
        XCTAssertEqual(report.clearCallDeclined, 0)
        XCTAssertEqual(report.clearCallAccuracy, 1.0, accuracy: 1e-9)
    }

    func test_unmatched_prediction_is_false_positive() {
        // One real bounce + one phantom far away in time -> FP, precision 0.5.
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .in, 1.0), pred(inPt, .in, 5.0)],
            reference: [ref(inPt, .in, 1.0)]
        )
        XCTAssertEqual(report.matchedCount, 1)
        XCTAssertEqual(report.falsePositives, 1)
        XCTAssertEqual(report.falseNegatives, 0)
        XCTAssertEqual(report.bouncePrecision, 0.5, accuracy: 1e-9)
        XCTAssertEqual(report.bounceRecall, 1.0, accuracy: 1e-9)
    }

    func test_unmatched_reference_is_false_negative() {
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .in, 1.0)],
            reference: [ref(inPt, .in, 1.0), ref(outPt, .out, 2.0)]
        )
        XCTAssertEqual(report.matchedCount, 1)
        XCTAssertEqual(report.falseNegatives, 1)
        XCTAssertEqual(report.bounceRecall, 0.5, accuracy: 1e-9)
    }

    func test_in_called_out_is_wrong_flip() {
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .out, 1.0)],
            reference: [ref(inPt, .in, 1.0)]
        )
        XCTAssertEqual(report.clearCallTotal, 1)
        XCTAssertEqual(report.clearCallWrong, 1)
        XCTAssertEqual(report.clearCallCorrect, 0)
        XCTAssertEqual(report.clearCallAccuracy, 0.0, accuracy: 1e-9)
    }

    func test_clear_ball_called_too_close_is_declined() {
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .tooCloseToCall, 1.0)],
            reference: [ref(inPt, .in, 1.0)]
        )
        XCTAssertEqual(report.clearCallDeclined, 1)
        XCTAssertEqual(report.clearCallWrong, 0)
        XCTAssertEqual(report.clearCallCorrect, 0)
    }

    func test_close_reference_honestly_flagged_is_correct() {
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .tooCloseToCall, 1.0)],
            reference: [ref(inPt, .tooCloseToCall, 1.0)]
        )
        XCTAssertEqual(report.closeCallTotal, 1)
        XCTAssertEqual(report.closeCallCorrect, 1)
        XCTAssertEqual(report.closeCallDecided, 0)
        XCTAssertEqual(report.closeCallAccuracy, 1.0, accuracy: 1e-9)
        // It must not be counted in the clear bucket.
        XCTAssertEqual(report.clearCallTotal, 0)
    }

    func test_close_reference_confidently_decided_is_counted_separately() {
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .in, 1.0)],
            reference: [ref(inPt, .tooCloseToCall, 1.0)]
        )
        XCTAssertEqual(report.closeCallTotal, 1)
        XCTAssertEqual(report.closeCallDecided, 1)
        XCTAssertEqual(report.closeCallCorrect, 0)
    }

    func test_court_error_distance_is_measured() {
        // Predicted 0.5 ft from the labeled point.
        let report = EvalRunner().evaluate(
            predicted: [pred(CGPoint(x: 10.5, y: 22), .in, 1.0)],
            reference: [ref(CGPoint(x: 10.0, y: 22), .in, 1.0)]
        )
        XCTAssertEqual(report.meanCourtErrorFeet, 0.5, accuracy: 1e-9)
        XCTAssertEqual(report.maxCourtErrorFeet, 0.5, accuracy: 1e-9)
    }

    func test_too_close_rate_counts_all_declines() {
        // 2 matched: one clear ball declined, one close ball honestly flagged -> both tooClose.
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .tooCloseToCall, 1.0), pred(outPt, .tooCloseToCall, 2.0)],
            reference: [ref(inPt, .in, 1.0),               ref(outPt, .tooCloseToCall, 2.0)]
        )
        XCTAssertEqual(report.matchedCount, 2)
        XCTAssertEqual(report.tooCloseRate, 1.0, accuracy: 1e-9)
    }

    func test_pairing_respects_time_tolerance() {
        // Same court point, but the prediction is 1 s late -> outside the 0.15 s window.
        let report = EvalRunner().evaluate(
            predicted: [pred(inPt, .in, 2.0)],
            reference: [ref(inPt, .in, 1.0)]
        )
        XCTAssertEqual(report.matchedCount, 0)
        XCTAssertEqual(report.falsePositives, 1)
        XCTAssertEqual(report.falseNegatives, 1)
    }

    func test_pairing_respects_court_distance_tolerance() {
        // Same time, but 10 ft apart -> outside the 3 ft proximity window.
        let report = EvalRunner().evaluate(
            predicted: [pred(CGPoint(x: 0, y: 22), .out, 1.0)],
            reference: [ref(CGPoint(x: 10, y: 22), .in, 1.0)]
        )
        XCTAssertEqual(report.matchedCount, 0)
        XCTAssertEqual(report.falsePositives, 1)
        XCTAssertEqual(report.falseNegatives, 1)
    }

    func test_greedy_match_picks_closest_when_two_candidates() {
        // One reference, two in-window predictions: the nearer (in time + court) should match.
        let report = EvalRunner().evaluate(
            predicted: [pred(CGPoint(x: 12.0, y: 22), .in, 1.10),   // ~2 ft, 0.10 s off
                        pred(CGPoint(x: 10.2, y: 22), .in, 1.02)],  // ~0.2 ft, 0.02 s off (closer)
            reference: [ref(CGPoint(x: 10.0, y: 22), .in, 1.0)]
        )
        XCTAssertEqual(report.matchedCount, 1)
        XCTAssertEqual(report.falsePositives, 1)
        // The closer prediction (0.2 ft) is the one matched.
        XCTAssertEqual(report.meanCourtErrorFeet, 0.2, accuracy: 1e-6)
    }

    func test_empty_inputs_are_well_defined() {
        let report = EvalRunner().evaluate(predicted: [], reference: [])
        XCTAssertEqual(report.matchedCount, 0)
        // No predictions and no references: vacuously perfect, not divide-by-zero.
        XCTAssertEqual(report.bouncePrecision, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.bounceRecall, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.tooCloseRate, 0.0, accuracy: 1e-9)
        XCTAssertEqual(report.meanCourtErrorFeet, 0.0, accuracy: 1e-9)
    }
}
