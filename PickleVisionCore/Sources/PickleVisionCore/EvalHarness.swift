import CoreGraphics
import Foundation

// MARK: - ReferenceBounce

/// Ground-truth label for a single bounce, sourced from the in-app tap-test.
///
/// The tap-test reads a court coordinate (and the in/out result) through `CourtModel`,
/// so the labeled court point lives in the same court-feet space as `JudgedBounce.courtPoint`.
///
/// Honesty caveat (see Phase B5 plan): a human tapping where a ball bounced is itself
/// imprecise to within roughly the same band the system is judged against, and that is
/// exactly where single-camera physics is weakest. Near-line ground truth is therefore
/// no more authoritative than the pipeline, so the eval runner leans on the
/// `tooCloseToCall` convention rather than treating a hand-tapped point as exact.
public struct ReferenceBounce: Equatable, Codable {
    /// The court-space coordinate where the ball actually bounced (feet, origin at court corner).
    public var courtPoint: CGPoint
    /// What the call should be: a clear `.in`/`.out`, or `.tooCloseToCall` when the labeler
    /// judged the bounce too near the line to call by eye.
    public var expectedVerdict: LineVerdict
    /// Approximate time of the bounce (seconds into the clip), used to pair with a prediction.
    public var time: TimeInterval

    public init(courtPoint: CGPoint, expectedVerdict: LineVerdict, time: TimeInterval) {
        self.courtPoint = courtPoint
        self.expectedVerdict = expectedVerdict
        self.time = time
    }
}

// MARK: - EvalReport

/// The measured outcome of running the in/out pipeline against ground truth.
///
/// Counts are reported alongside rates on purpose: this is a personal tool measured on
/// a handful of clips, where a single mislabeled bounce can swing a rate, so the raw
/// counts keep the rates honest (see Phase B5 plan, risks).
///
/// Call accuracy is split into two buckets because a single blended number hides the
/// part that matters: clear `.in`/`.out` balls should be near-perfect, while genuinely
/// near-line balls should be honestly flagged `.tooCloseToCall` rather than confidently
/// (and arbitrarily) decided. A `.tooCloseToCall` on a near-line reference is a correct
/// outcome, not a miss.
public struct EvalReport: Equatable {
    /// Total ground-truth bounces.
    public var referenceCount: Int
    /// Total pipeline-predicted bounces.
    public var predictedCount: Int
    /// Predicted bounces paired to a reference (true positives).
    public var matchedCount: Int
    /// Predicted bounces with no matching reference (phantom detections).
    public var falsePositives: Int
    /// Reference bounces with no matching prediction (missed bounces).
    public var falseNegatives: Int

    /// Matched pairs whose reference is a clear `.in`/`.out`.
    public var clearCallTotal: Int
    /// Clear references the pipeline called correctly (exact verdict match).
    public var clearCallCorrect: Int
    /// Clear references the pipeline called as the opposite side (in<->out) -- the dangerous error.
    public var clearCallWrong: Int
    /// Clear references the pipeline declined as `.tooCloseToCall` (over-conservative miss).
    public var clearCallDeclined: Int

    /// Matched pairs whose reference is `.tooCloseToCall` (genuinely near the line).
    public var closeCallTotal: Int
    /// Near-line references the pipeline honestly flagged `.tooCloseToCall` (correct).
    public var closeCallCorrect: Int
    /// Near-line references the pipeline confidently decided `.in`/`.out` (counted, not scored as right).
    public var closeCallDecided: Int

    /// Per matched pair, the court-space distance (feet) between prediction and reference.
    /// Note: prediction and ground truth share the same `CourtModel`, so calibration error
    /// partly cancels here -- read this as relative error, not absolute physical accuracy.
    public var courtErrorsFeet: [Double]

    public init(
        referenceCount: Int = 0,
        predictedCount: Int = 0,
        matchedCount: Int = 0,
        falsePositives: Int = 0,
        falseNegatives: Int = 0,
        clearCallTotal: Int = 0,
        clearCallCorrect: Int = 0,
        clearCallWrong: Int = 0,
        clearCallDeclined: Int = 0,
        closeCallTotal: Int = 0,
        closeCallCorrect: Int = 0,
        closeCallDecided: Int = 0,
        courtErrorsFeet: [Double] = []
    ) {
        self.referenceCount = referenceCount
        self.predictedCount = predictedCount
        self.matchedCount = matchedCount
        self.falsePositives = falsePositives
        self.falseNegatives = falseNegatives
        self.clearCallTotal = clearCallTotal
        self.clearCallCorrect = clearCallCorrect
        self.clearCallWrong = clearCallWrong
        self.clearCallDeclined = clearCallDeclined
        self.closeCallTotal = closeCallTotal
        self.closeCallCorrect = closeCallCorrect
        self.closeCallDecided = closeCallDecided
        self.courtErrorsFeet = courtErrorsFeet
    }

    /// matched / (matched + false positives). Vacuously 1.0 when nothing was predicted.
    public var bouncePrecision: Double {
        let denom = matchedCount + falsePositives
        return denom == 0 ? 1.0 : Double(matchedCount) / Double(denom)
    }
    /// matched / (matched + false negatives). Vacuously 1.0 when there was nothing to find.
    public var bounceRecall: Double {
        let denom = matchedCount + falseNegatives
        return denom == 0 ? 1.0 : Double(matchedCount) / Double(denom)
    }
    /// Correct clear calls / total clear calls. Vacuously 1.0 when there were none.
    public var clearCallAccuracy: Double {
        clearCallTotal == 0 ? 1.0 : Double(clearCallCorrect) / Double(clearCallTotal)
    }
    /// Honest declines / total close calls. Vacuously 1.0 when there were none.
    public var closeCallAccuracy: Double {
        closeCallTotal == 0 ? 1.0 : Double(closeCallCorrect) / Double(closeCallTotal)
    }
    /// Fraction of matched bounces the pipeline declined as `.tooCloseToCall`
    /// (clear balls declined + near-line balls honestly flagged).
    public var tooCloseRate: Double {
        matchedCount == 0 ? 0.0 : Double(clearCallDeclined + closeCallCorrect) / Double(matchedCount)
    }
    /// Mean court-space error (feet) over matched pairs; 0 when there are none.
    public var meanCourtErrorFeet: Double {
        courtErrorsFeet.isEmpty ? 0.0 : courtErrorsFeet.reduce(0, +) / Double(courtErrorsFeet.count)
    }
    /// Worst court-space error (feet) over matched pairs; 0 when there are none.
    public var maxCourtErrorFeet: Double {
        courtErrorsFeet.max() ?? 0.0
    }
}

// MARK: - EvalRunner

/// Scores pipeline output (`[JudgedBounce]`) against ground truth (`[ReferenceBounce]`).
///
/// It pairs each prediction to at most one reference (and vice versa) by a time window
/// AND a court-proximity window, greedily assigning the closest pairs first, then tallies
/// detection metrics (precision/recall) and call accuracy split into clear vs close buckets.
///
/// The two tolerances are unverified knobs: their right values depend on real bounce
/// cadence and labeling precision and should be tuned against the first real clips, not
/// trusted as-is (see Phase B5 plan, decisions).
public struct EvalRunner {
    /// Max |prediction time - reference time| (seconds) for a pair to be eligible.
    public var timeToleranceSeconds: TimeInterval
    /// Max court-space distance (feet) for a pair to be eligible.
    public var distanceToleranceFeet: Double

    public init(timeToleranceSeconds: TimeInterval = 0.15, distanceToleranceFeet: Double = 3.0) {
        self.timeToleranceSeconds = timeToleranceSeconds
        self.distanceToleranceFeet = distanceToleranceFeet
    }

    public func evaluate(predicted: [JudgedBounce], reference: [ReferenceBounce]) -> EvalReport {
        // 1. Enumerate every prediction/reference pair that falls inside both windows.
        struct Candidate { let p: Int; let r: Int; let dist: Double; let dt: TimeInterval }
        var candidates: [Candidate] = []
        for (pi, p) in predicted.enumerated() {
            for (ri, r) in reference.enumerated() {
                let dt = abs(p.bounce.time - r.time)
                guard dt <= timeToleranceSeconds else { continue }
                let d = courtDistance(p.courtPoint, r.courtPoint)
                guard d <= distanceToleranceFeet else { continue }
                candidates.append(Candidate(p: pi, r: ri, dist: d, dt: dt))
            }
        }

        // 2. Greedy one-to-one: take the closest pair (by court distance, tie-break by time)
        //    and consume both endpoints, so each prediction/reference matches at most once.
        candidates.sort { $0.dist != $1.dist ? $0.dist < $1.dist : $0.dt < $1.dt }

        var predMatched = [Bool](repeating: false, count: predicted.count)
        var refMatched  = [Bool](repeating: false, count: reference.count)
        var matches: [(p: Int, r: Int, dist: Double)] = []
        for c in candidates {
            if predMatched[c.p] || refMatched[c.r] { continue }
            predMatched[c.p] = true
            refMatched[c.r] = true
            matches.append((c.p, c.r, c.dist))
        }

        // 3. Tally.
        var report = EvalReport()
        report.referenceCount = reference.count
        report.predictedCount = predicted.count
        report.matchedCount = matches.count
        report.falsePositives = predMatched.lazy.filter { !$0 }.count
        report.falseNegatives = refMatched.lazy.filter { !$0 }.count

        for m in matches {
            let predVerdict = predicted[m.p].call.verdict
            let refVerdict  = reference[m.r].expectedVerdict
            report.courtErrorsFeet.append(m.dist)

            switch refVerdict {
            case .in, .out:
                report.clearCallTotal += 1
                if predVerdict == refVerdict {
                    report.clearCallCorrect += 1
                } else if predVerdict == .tooCloseToCall {
                    report.clearCallDeclined += 1
                } else {
                    report.clearCallWrong += 1   // called the opposite side
                }
            case .tooCloseToCall:
                report.closeCallTotal += 1
                if predVerdict == .tooCloseToCall {
                    report.closeCallCorrect += 1
                } else {
                    report.closeCallDecided += 1
                }
            }
        }

        return report
    }

    private func courtDistance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
